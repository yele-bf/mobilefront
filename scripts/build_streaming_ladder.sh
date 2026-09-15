#!/usr/bin/env bash
# Construit l'échelle HLS de test de streaming Yélé (720p / 1080p / 2160p) à
# partir de Big Buck Bunny, prête à téléverser telle quelle sur un hébergement
# statique (Netlify, S3+CloudFront, GitHub Pages…).
#
# Usage :
#   ./scripts/build_streaming_ladder.sh [dossier_sortie]      # défaut: out/stream
#   CLIP_START=60 CLIP_DUR=180 SRC_URL=... ./scripts/build_streaming_ladder.sh
#
# Dépendances : curl, ffmpeg et Shaka Packager (`packager`, binaire unique à
# télécharger depuis https://github.com/shaka-project/shaka-packager/releases,
# ou `apt install shaka-packager` / `brew install shaka-packager`).
#
# Sortie : <dossier>/master.m3u8 + un dossier par palier (720p/, 1080p/,
# 2160p/), segments fMP4 de 4 s. Téléverser TOUT le dossier tel quel.
#
# CORS : le WebView de l'app charge la page depuis http://127.0.0.1:<port>, le
# CDN doit donc répondre `Access-Control-Allow-Origin: *` sur les manifestes ET
# les segments. Sur Netlify, le fichier `_headers` généré ici s'en charge ; sur
# S3/CloudFront, ajouter la politique de réponse équivalente.
set -euo pipefail

OUT="${1:-out/stream}"
CLIP_START="${CLIP_START:-60}"   # début du clip dans la source (s)
CLIP_DUR="${CLIP_DUR:-180}"      # durée du clip (s) — 3 min ≈ 1 Go en 4K
SRC_URL="${SRC_URL:-https://upload.wikimedia.org/wikipedia/commons/c/c0/Big_Buck_Bunny_4K.webm}"

PACKAGER="${PACKAGER:-packager}"
FFMPEG="${FFMPEG:-ffmpeg}"

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "── 1/3 Source : $SRC_URL"
SRC="$WORK/source.webm"
curl -L --fail -o "$SRC" "$SRC_URL"

echo "── 2/3 Clip ${CLIP_DUR}s à t=${CLIP_START}s (réencodage H.264/AAC)"
CLIP="$WORK/clip.mp4"
"$FFMPEG" -hide_banner -loglevel error -y \
  -ss "$CLIP_START" -i "$SRC" -t "$CLIP_DUR" \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 96k -ac 2 \
  "$CLIP"

# Encode un palier et l'empaquette en HLS fMP4 (init + segments 4 s).
encode_one() { # $1=hauteur $2=débit_vidéo_kbps
  local H="$1" VB="$2" DIR="$OUT/${H}p"
  mkdir -p "$DIR"
  echo "── 3/3 palier ${H}p @ ${VB} kb/s"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$CLIP" -vf "scale=-2:${H}" -c:v libx264 -preset medium -b:v "${VB}k" \
    -maxrate "${VB}k" -bufsize "$((VB * 2))k" -g 120 -pix_fmt yuv420p \
    -c:a aac -b:a 96k -ac 2 \
    "$WORK/in_${H}p.mp4"
  "$PACKAGER" \
    "in=$WORK/in_${H}p.mp4,stream=video,init_segment=$DIR/init.mp4,segment_template=$DIR/\$Number\$.m4s,playlist_name=$DIR/media.m3u8" \
    "in=$WORK/in_${H}p.mp4,stream=audio,init_segment=$DIR/a_init.mp4,segment_template=$DIR/a_\$Number\$.m4s,playlist_name=$DIR/a_media.m3u8" \
    --hls_master_playlist_output="$DIR/playlist.m3u8" \
    --segment_duration=4 \
    >/dev/null
  rm -f "$WORK/in_${H}p.mp4"
}

# Débits cibles : 720p ≈ 4 Mb/s, 1080p ≈ 8 Mb/s, 2160p ≈ 16 Mb/s — alignés sur
# les paliers YouTube pour que les chiffres du tableau restent comparables.
encode_one 720 4000
encode_one 1080 8000
encode_one 2160 16000

echo "── Master playlist"
cat > "$OUT/master.m3u8" <<'EOF'
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-STREAM-INF:BANDWIDTH=4300000,AVERAGE-BANDWIDTH=4100000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",FRAME-RATE=30.000
720p/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8300000,AVERAGE-BANDWIDTH=8100000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",FRAME-RATE=30.000
1080p/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=16300000,AVERAGE-BANDWIDTH=16100000,RESOLUTION=3840x2160,CODECS="avc1.640033,mp4a.40.2",FRAME-RATE=30.000
2160p/playlist.m3u8
EOF

echo "── CORS + cache (fichier _headers Netlify)"
cat > "$OUT/_headers" <<'EOF'
/*
  Access-Control-Allow-Origin: *
  Access-Control-Allow-Headers: origin, range, accept-encoding, referer
  Access-Control-Expose-Headers: Content-Length, Content-Range
  Access-Control-Allow-Methods: GET, HEAD, OPTIONS
  Cache-Control: public, max-age=86400
EOF

echo "✔ Terminé : téléversez le contenu de '$OUT' tel quel."
echo "  Test local : python3 -m http.server 8080 -d '$OUT'"
echo "  puis ouvrir http://localhost:8080/master.m3u8"
