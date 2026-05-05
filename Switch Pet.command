#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

clear
printf '\\n'
printf '  Xiaoer Pet Switcher\\n'
printf '  -------------------\\n\\n'

if [[ -x "scripts/apply-command-icon.sh" ]]; then
  "scripts/apply-command-icon.sh" "assets/xiaoer-ear-install-icon.png" "$0" >/dev/null 2>&1 || true
fi

"scripts/switch-pet.sh"

printf '\\nDone.\\n\\n'
read -r -p "Press Enter to close this window..."
