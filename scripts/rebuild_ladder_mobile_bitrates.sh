#!/usr/bin/env bash
# Rebuild l'échelle HLS de test Yélé aux DÉBITS SERVIS PAR YOUTUBE SUR MOBILE
# (H.264 30 fps : 720p ≈ 2,5 Mb/s, 1080p ≈ 4 Mb/s — l'échelle Akamai d'origine
# pesait 4,95 / 9,91 Mb/s, bien au-dessus de ce qu'un lecteur mobile reçoit
# réellement : YouTube sert ~2,5 Mb/s en 720p et ~3,5-4 Mb/s en 1080p).
#
# Principe : les segments fMP4 d'origine (init *_0 + segments numérotés) sont
# CONCATÉNÉS binaires en un fichier continu (les truns portent des
# base_data_offset implicites — c'est le montage utilisé pour construire
# l'échelle initiale), puis ré-encodés H.264 aux débits cibles avec GOP 1 s
# indépendant (-g 30 -keyint_min 30 -sc_threshold 0 : segments découpables au
# cordeau, +48 profils sans B-pyramide hors référence). L'audio HE-AAC 64k
# d'origine est conservé tel quel (recopié, jamais ré-encodé).
#
# Sortie : out/stream/bbb-mobile/ prêt à être copié dans stream-assets/bbb/ et
# redéployé (NETLIFY_TOKEN=… scripts/deploy_netlify.sh).
#
# Usage :
#   ./scripts/rebuild_ladder_mobile_bitrates.sh [src] [dst]
#     src défaut : ../../stream-assets/bbb  (assets publiés)
#     dst défaut : out/stream/bbb-mobile
set -euo pipefail

SRC="${1:-../../stream-assets/bbb}"
DST="${2:-out/stream/bbb-mobile}"
GITROOT="$(cd "$(dirname "$0")/.." && pwd)"   # racine du dépôt mobilefront
TOOLS="$(cd "$GITROOT/../../tools" && pwd)"    # binaires statiques du workspace
FFMPEG="${FFMPEG:-$TOOLS/ffmpeg}"
FP="${FP:-$TOOLS/ffprobe}"

# Débits cibles (b:v) — calés sur le lecteur YouTube mobile 30 fps.
declare -A VBW=( [720]=2500k [1080]=4000k [2160]=12000k )
declare -A BUFSIZE=( [720]=2500k [1080]=4000k [2160]=12000k )
declare -A MAXRATE=( [720]=2500k [1080]=4000k [2160]=12000k )
declare -A RES=( [720]=1280x720 [1080]=1920x1080 [2160]=3840x2160 )
# Cartouche source gravé dans les pixels par Akamai, DEUX zones effacées :
# 1. « 1280x720 / 4000 kbps » (haut) : affichait le débit de la variante
#    D'ORIGINE, pas celui du ré-encodage — trompeur.
# 2. Compteur « Frame N: PTS= 00:00:SS.mmm » (jaune sur boîte noire, milieu) :
#    effacé le 18/09 (demande utilisateur) — il n'apportait la preuve de
#    lecture réelle qu'en capture, et polluait la vidéo de campagne.
# Boîtes du compteur mesurées par bbox jaune sur 9 instants (source continue
# 720p : x 362..918, y 432..461 — compteur FIXE ; inclut la bordure jaune
# gauche que la mesure « pixels sombres » seule ratait, d'où un résidu au
# 1er essai). Les autres paliers = ×1,5 et ×3 SAUF le bord droit du 2160p :
# le texte y est proportionnellement plus large (0,753 de la largeur vs 0,717)
# — mesuré par frame, pas déduit. Marge ~15-40 px.
declare -A DELOGO=( [720]="delogo=x=360:y=60:w=560:h=60,delogo=x=345:y=415:w=590:h=62" \
                    [1080]="delogo=x=540:y=90:w=840:h=90,delogo=x=520:y=624:w=884:h=92" \
                    [2160]="delogo=x=1080:y=180:w=1680:h=180,delogo=x=1060:y=1250:w=1870:h=180" )
VARIANT_DIRS=( "bbb_30fps_1280x720_4000k" "bbb_30fps_1920x1080_8000k" "bbb_30fps_3840x2160_12000k" )
HEIGHTS=( 720 1080 2160 )

mkdir -p "$DST"
echo "── 1. Fichiers continus par palier (concat binaire init + segments)"
for i in "${!VARIANT_DIRS[@]}"; do
  dir="${VARIANT_DIRS[$i]}"
  h="${HEIGHTS[$i]}"
  out="$DST/continuous_${h}p.mp4"
  if [ -s "$out" ]; then
    echo "   $out déjà présent, sauté"
    continue
  fi
  cat "$SRC/$dir/${dir}_0.m4v" "$SRC/$dir/${dir}_"*.m4v > "$out"
  echo "   $out : $(du -h "$out" | cut -f1)"
done

echo "── 2. Ré-encodage vidéo aux débits cibles"
for i in "${!VARIANT_DIRS[@]}"; do
  dir="${VARIANT_DIRS[$i]}"
  h="${HEIGHTS[$i]}"
  out="$DST/${dir}_reencoded.mp4"
  [ -s "$out" ] && { echo "   $out déjà présent, sauté"; continue; }
  echo "   ${h}p → ${VBW[$h]} : encodage en cours…"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$DST/continuous_${h}p.mp4" \
    -c:v libx264 -b:v "${VBW[$h]}" -maxrate "${MAXRATE[$h]}" \
    -bufsize "${BUFSIZE[$h]}" -preset veryfast \
    -g 30 -keyint_min 30 -sc_threshold 0 \
    -profile:v high -pix_fmt yuv420p \
    -vf "${DELOGO[$h]},scale=${RES[$h]}" \
    -an "$out"
done

echo "── 3. Segmentation fMP4 (packager Shaka) + recopie audio d'origine"
for i in "${!VARIANT_DIRS[@]}"; do
  dir="${VARIANT_DIRS[$i]}"
  h="${HEIGHTS[$i]}"
  BW=$(( $(echo "${VBW[$h]}" | tr -d 'k') * 1000 + 67071 + 250000 ))
  mkdir -p "$DST/$dir"
  rm -f "$DST/$dir/${dir}_"*.m4v
  "$TOOLS/packager" --segment_duration 4 \
    "input=$DST/${dir}_reencoded.mp4,stream=video,init_segment=$DST/$dir/${dir}_0.m4v,segment_template=$DST/$dir/${dir}_\$Number\$.m4v" \
    > /dev/null
  echo "   ${h}p : $(ls "$DST/$dir" | wc -l) fichiers (bandwidth HLS $BW)"
  declare -p BW > /dev/null   # garde BW vivant pour le manifeste
  BANDWIDTHS[$i]=$BW
done

mkdir -p "$DST/bbb_a64k"
cp -n "$SRC/bbb_a64k/"*.m4a "$DST/bbb_a64k/" 2>/dev/null || true

echo "── 4. Manifestes HLS (build_master_playlist.py)"
BANDWIDTH_720=${BANDWIDTHS[0]} BANDWIDTH_1080=${BANDWIDTHS[1]} \
BANDWIDTH_2160=${BANDWIDTHS[2]} \
python3 "$GITROOT/scripts/build_master_playlist.py" "$DST"

echo "── 5. Vérification du débit réel produit"
for i in "${!VARIANT_DIRS[@]}"; do
  dir="${VARIANT_DIRS[$i]}"
  h="${HEIGHTS[$i]}"
  "$FP" -v error -show_entries format=bit_rate -of csv=p=0 "$DST/${dir}_reencoded.mp4" \
    | awk -v h="$h" '{printf "   %sp : %.2f Mb/s\n", h, $1/1e6}'
done

echo "── Terminé. Copier vers stream-assets puis redéployer :"
echo "   cp -r $DST/* <racine>/stream-assets/bbb/ && NETLIFY_TOKEN=… scripts/deploy_netlify.sh"
