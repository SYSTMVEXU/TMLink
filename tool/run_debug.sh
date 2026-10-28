#!/usr/bin/env bash
set -euo pipefail

ATS_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ATS_REPO_ROOT"

# Optionally load the ignored local setup file into this process. Flutter and
# the app receive the values only through their inherited process environment.
if [[ -z "${VEX_TM_CLIENT_ID:-}" && -z "${VEX_TM_CLIENT_SECRET:-}" && -f set-credentials.sh ]]; then
  source set-credentials.sh >/dev/null 2>&1
fi

if [[ -z "${VEX_TM_CLIENT_ID:-}" || -z "${VEX_TM_CLIENT_SECRET:-}" ]]; then
  echo "Set VEX_TM_CLIENT_ID and VEX_TM_CLIENT_SECRET in this shell, or create the ignored set-credentials.sh file." >&2
  exit 1
fi

exec flutter run "$@"
