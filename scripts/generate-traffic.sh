#!/usr/bin/env bash
# Generates realistic traffic for the dashboard: listings, reads, uploads, and some errors.
# Usage:  bash scripts/generate-traffic.sh [minutes]     (default 5)
set -uo pipefail
source "$(dirname "$0")/00-env.sh" >/dev/null
MINUTES="${1:-5}"; END=$(( $(date +%s) + MINUTES * 60 ))
TMP="$(mktemp)"; echo "traffic generator test file" > "$TMP"

echo "Sending traffic to $URL for $MINUTES min (Ctrl+C to stop)"
while [ "$(date +%s)" -lt "$END" ]; do
  TOKEN="$(gcloud auth print-identity-token)"
  H="Authorization: Bearer $TOKEN"
  for i in $(seq 1 8); do
    curl -s -o /dev/null -H "$H" "$URL/" &
    curl -s -o /dev/null -H "$H" "$URL/files" &
    curl -s -o /dev/null -H "$H" "$URL/files/reports/sales_by_city.csv" &
    (( RANDOM % 3 == 0 )) && curl -s -o /dev/null -H "$H" "$URL/files/does-not-exist.csv" &   # 404
    (( RANDOM % 4 == 0 )) && curl -s -o /dev/null "$URL/files" &                              # 403, no token
  done
  curl -s -o /dev/null -X POST -H "$H" "$URL/upload" -F "file=@$TMP;filename=traffic.txt" &
  wait; printf "."; sleep 3
done
echo; echo "Done."
