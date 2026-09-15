#!/usr/bin/env bash
# Construit localement l'échelle de test de streaming Yélé en téléchargeant les
# segments fMP4 d'origine (aucun ré-encodage : débits et qualité identiques au
# CDN Akamai) depuis le ladder DASH public Big Buck Bunny 30 fps :
#   https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd
# Segmentation périodique : 4,0 s (vidéo, timescale 30, duration=120) et
# ~4,01 s (audio HE-AAC 64k, timescale 48000, duration=192512).
#
# Usage :
#   ./scripts/fetch_akamai_clip.sh [dossier_sortie]   # défaut : out/stream/bbb
#   SEG_START=1 SEG_COUNT=45 ./scripts/fetch_akamai_clip.sh   # clip de 3 min
#
# Idempotent : les fichiers déjà présents (non vides) ne sont pas retéléchargés.
# Génère ensuite master.m3u8 via scripts/build_master_playlist.py.
set -euo pipefail

BASE="${AKAMAI_BASE:-https://dash.akamaized.net/akamai/bbb_30fps}"
OUT="${1:-out/stream/bbb}"
SEG_START="${SEG_START:-1}"
SEG_COUNT="${SEG_COUNT:-45}"
# Chaîne (pas un tableau : elle doit traverser l'environnement des sous-shells).
REPS_V="bbb_30fps_1280x720_4000k bbb_30fps_1920x1080_8000k bbb_30fps_3840x2160_12000k"
REP_A="bbb_a64k"                # HE-AAC 64k
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

download_segment() {
  local i=$1
  for r in $REPS_V; do
    local f="$OUT/$r/${r}_$i.m4v"
    [ -s "$f" ] || curl -sf --retry 4 --retry-delay 2 --max-time 120 \
      -o "$f" "$BASE/$r/${r}_$i.m4v" || return 1
  done
  local fa="$OUT/$REP_A/${REP_A}_$i.m4a"
  [ -s "$fa" ] || curl -sf --retry 4 --retry-delay 2 --max-time 120 \
    -o "$fa" "$BASE/$REP_A/${REP_A}_$i.m4a" || return 1
  printf 'segment %s ok\n' "$i"
}
export BASE OUT REPS_V REP_A
export -f download_segment

mkdir -p "$OUT"
for r in $REPS_V; do mkdir -p "$OUT/$r"; done
mkdir -p "$OUT/$REP_A"

echo "=== Initialisation (moov) des 4 pistes ==="
for r in $REPS_V; do
  f="$OUT/$r/${r}_0.m4v"
  [ -s "$f" ] || curl -sf --retry 4 --retry-delay 2 --max-time 120 \
    -o "$f" "$BASE/$r/${r}_0.m4v"
done
f="$OUT/$REP_A/${REP_A}_0.m4a"
[ -s "$f" ] || curl -sf --retry 4 --retry-delay 2 --max-time 120 \
  -o "$f" "$BASE/$REP_A/${REP_A}_0.m4a"

echo "=== Segments $SEG_START..$((SEG_START + SEG_COUNT - 1)) (4 fichiers par segment, 6 en parallèle) ==="
seq "$SEG_START" $((SEG_START + SEG_COUNT - 1)) \
  | xargs -P 6 -I{} bash -c 'download_segment "$@"' _ {}

echo "=== Génération de master.m3u8 ==="
python3 "$SCRIPT_DIR/build_master_playlist.py" "$OUT"

echo "=== Terminé : $(du -sh "$OUT" | cut -f1) dans $OUT ==="
