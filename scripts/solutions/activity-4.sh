#!/usr/bin/env bash
# SOLUTION — Activity 4 (Monitoring dashboard). Use it only if you get stuck.
set -euo pipefail
source "$(dirname "$0")/../00-env.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

gcloud monitoring dashboards create --config-from-file="$ROOT/monitoring/dashboard-solution.json"
bash "$ROOT/scripts/generate-traffic.sh" 3
