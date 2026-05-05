#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

clear
printf '\\n'
printf '  Xiaoer Hammerspoon Pet Installer\\n'
printf '  --------------------------------\\n\\n'

if [[ -x "scripts/apply-command-icon.sh" ]]; then
  "scripts/apply-command-icon.sh" "assets/xiaoer-ear-install-icon.png" "$0" >/dev/null 2>&1 || true
fi

if [[ ! -d "/Applications/Hammerspoon.app" && ! -d "${HOME}/Applications/Hammerspoon.app" ]]; then
  printf 'Hammerspoon is not installed yet.\\n'
  printf 'Opening the Hammerspoon download page...\\n\\n'
  open "https://www.hammerspoon.org/"
  printf 'Install Hammerspoon first, then run this installer again.\\n\\n'
  read -r -p "Press Enter to close this window..."
  exit 1
fi

printf 'Installing Xiaoer Pet into ~/.hammerspoon/pai ...\\n\\n'
"scripts/install.sh"

printf '\\nDone. If the pet does not appear, open Hammerspoon and choose Reload Config.\\n\\n'
read -r -p "Press Enter to close this window..."
