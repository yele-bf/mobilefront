#!/usr/bin/env bash
# Déploie le dossier stream-assets (échelle HLS BBB + _headers + index.html) sur
# Netlify via l'API « zip deploy » — aucun CLI requis, seulement curl + python3.
#
# Usage :
#   NETLIFY_TOKEN=<jeton> ./scripts/deploy_netlify.sh [dossier_assets] [nom_de_site...]
#
#   dossier_assets : défaut <racine>/stream-assets (publié tel quel à la racine du site)
#   nom_de_site... : noms essayés dans l'ordre (défaut : yele-test-assets, -bbb, -stream)
#
# Jeton : https://app.netlify.com/user/applications → New access token.
# Réidempotent : si le nom de site est déjà pris (HTTP 409), le site existant est
# réutilisé et un nouveau déploiement est publié par-dessus.
set -euo pipefail

cd "$(dirname "$0")/.."                        # racine du dépôt mobilefront
ASSETS="${1:-../../stream-assets}"
shift || true
NAMES=("$@")
[ ${#NAMES[@]} -eq 0 ] && NAMES=(yele-test-assets yele-test-assets-bbb yele-test-assets-stream)

TOKEN="${NETLIFY_TOKEN:?NETLIFY_TOKEN manquant — créez-le sur https://app.netlify.com/user/applications}"
API="https://api.netlify.com/api/v1"
ZIP="$(pwd)/out/yele-deploy.zip"
mkdir -p out

json() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('$1','') if isinstance(d,dict) else '')"; }

echo "── 1. Archive zip de $ASSETS"
rm -f "$ZIP"
( cd "$ASSETS" && zip -qr0 "$ZIP" . -x ".git/*" )
ls -lh "$ZIP" | awk '{print "   taille :", $5}'

echo "── 2. Création ou réutilisation du site"
SITE_ID=""; SITE_URL=""
for name in "${NAMES[@]}"; do
  code=$(curl -s -o out/netlify_site.json -w '%{http_code}' -X POST "$API/sites" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"$name\"}")
  if [ "$code" = "201" ]; then
    SITE_ID=$(json id < out/netlify_site.json); SITE_URL=$(json ssl_url < out/netlify_site.json)
    echo "   site créé : $SITE_URL"; break
  elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
    echo "JETON REFUSÉ (HTTP $code) — vérifiez le token."; exit 1
  fi
  # Nom pris : le site existe-t-il déjà sur ce compte ? (réidempotence)
  curl -s "$API/sites?name=$name" -H "Authorization: Bearer $TOKEN" -o out/netlify_sites.json
  SITE_ID=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d[0]['id'] if isinstance(d,list) and d else '')" < out/netlify_sites.json)
  if [ -n "$SITE_ID" ]; then
    SITE_URL=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d[0].get('ssl_url',''))" < out/netlify_sites.json)
    echo "   site existant réutilisé : $SITE_URL"; break
  fi
  echo "   nom '$name' indisponible, essai suivant…"
done
if [ -z "$SITE_ID" ]; then
  code=$(curl -s -o out/netlify_site.json -w '%{http_code}' -X POST "$API/sites" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}')
  [ "$code" = "201" ] || { echo "ÉCHEC création site (HTTP $code)"; cat out/netlify_site.json; exit 1; }
  SITE_ID=$(json id < out/netlify_site.json); SITE_URL=$(json ssl_url < out/netlify_site.json)
  echo "   site créé (nom auto-attribué) : $SITE_URL"
fi

echo "── 3. Upload du zip (plusieurs minutes selon la bande montante)"
code=$(curl -s --max-time 540 -o out/netlify_deploy.json -w '%{http_code}' \
  -X POST "$API/sites/$SITE_ID/deploys" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/zip" \
  --data-binary "@$ZIP")
[ "$code" = "200" ] || { echo "ÉCHEC upload (HTTP $code)"; cat out/netlify_deploy.json; exit 1; }
DEPLOY_ID=$(json id < out/netlify_deploy.json)
echo "   déploiement $DEPLOY_ID accepté — traitement côté Netlify…"

echo "── 4. Attente de l'état 'ready' (jusqu'à ~90 s)"
for _ in $(seq 1 9); do
  sleep 10
  curl -s "$API/sites/$SITE_ID/deploys/$DEPLOY_ID" -H "Authorization: Bearer $TOKEN" -o out/netlify_deploy.json
  state=$(json state < out/netlify_deploy.json)
  echo "   état : $state"
  [ "$state" = "ready" ] && break
  if [ "$state" = "error" ]; then echo "ERREUR Netlify :"; cat out/netlify_deploy.json; exit 1; fi
done
if [ "$(json state < out/netlify_deploy.json)" != "ready" ]; then
  echo "Toujours en traitement — re-sonder avec :"
  echo "  curl -s \"$API/sites/$SITE_ID/deploys/$DEPLOY_ID\" -H \"Authorization: Bearer \$NETLIFY_TOKEN\" | python3 -c \"import json,sys;print(json.load(sys.stdin)['state'])\""
  exit 2
fi

echo "── 5. Vérification publique"
echo "   master :"
curl -sI "$SITE_URL/bbb/master.m3u8" | grep -iE '^(HTTP|access-control|content-type|content-length)' | sed 's/^/     /'
SEG="bbb_30fps_3840x2160_12000k/bbb_30fps_3840x2160_12000k_0.m4v"
echo "   segment 2160p (Origin WebView simulée) :"
curl -sI -H "Origin: http://127.0.0.1:8080" "$SITE_URL/bbb/$SEG" \
  | grep -iE '^(HTTP|access-control|content-length)' | sed 's/^/     /'
echo "OK — URL à mettre dans l'app : $SITE_URL/bbb/master.m3u8"
