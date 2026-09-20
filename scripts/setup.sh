#!/bin/bash
# Keys from .env into the Keychain, then build, install and launch the macOS app.
# Usage: scripts/setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env — put your keys in it, then run this again." >&2
  exit 1
fi

set -a; . ./.env; set +a

store() { # store <account> <value>
  security add-generic-password -U -s local.lyra -a "$1" -w "$2" >/dev/null
  echo "Stored $1 in the Keychain."
}

[[ -n "${TYPESAFE_API_KEY:-}" ]] || { echo "TYPESAFE_API_KEY is empty in .env" >&2; exit 1; }
store typesafe-api-key "$TYPESAFE_API_KEY"
[[ -n "${OPENROUTER_API_KEY:-}" ]] && store openrouter-api-key "$OPENROUTER_API_KEY"

bash scripts/mac.sh --run
