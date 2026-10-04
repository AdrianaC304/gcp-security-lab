#!/usr/bin/env bash
# Generates realistic traffic for the dashboard: listings, reads, uploads, and some errors (401/403/404).
# Usage:  bash scripts/generate-traffic.sh [minutes]     (default 5)
set -uo pipefail
source "$(dirname "$0")/00-env.sh" >/dev/null
MINUTES="${1:-5}"; END=$(( $(date +%s) + MINUTES * 60 ))
TMP="$(mktemp)"; echo "traffic generator test file" > "$TMP"

[ -n "${API_KEY:-}" ] || { echo "No API key: finish Activity 1 first (the secret must exist)."; exit 1; }

echo "Sending traffic to $URL for $MINUTES min (Ctrl+C to stop)"
while [ "$(date +%s)" -lt "$END" ]; do
  TOKEN="$(gcloud auth print-identity-token)"
  H="Authorization: Bearer $TOKEN"; K="X-API-Key: $API_KEY"
  for i in $(seq 1 8); do
    curl -s -o /dev/null -H "$H" "$URL/" &
    curl -s -o /dev/null -H "$H" -H "$K" "$URL/files" &
    curl -s -o /dev/null -H "$H" -H "$K" "$URL/files/reports/sales_by_city.csv" &
    (( RANDOM % 3 == 0 )) && curl -s -o /dev/null -H "$H" -H "$K" "$URL/files/does-not-exist.csv" &   # 404
    (( RANDOM % 4 == 0 )) && curl -s -o /dev/null "$URL/files" &                                       # 403, no token
    (( RANDOM % 5 == 0 )) && curl -s -o /dev/null -H "$H" -H "X-API-Key: wrong" "$URL/files" &         # 401, bad key
  done
  curl -s -o /dev/null -X POST -H "$H" -H "$K" "$URL/upload" -F "file=@$TMP;filename=traffic.txt" &
  wait; printf "."; sleep 3
done
echo; echo "Done."
