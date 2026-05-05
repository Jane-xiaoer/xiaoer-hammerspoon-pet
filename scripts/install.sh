#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hammerspoon_dir="${HOME}/.hammerspoon"

mkdir -p "${hammerspoon_dir}"
rsync -a --delete "${repo_root}/pai/" "${hammerspoon_dir}/pai/"

if [[ ! -f "${hammerspoon_dir}/pai/local_config.json" ]]; then
  sed "s#/Users/YOUR_NAME#${HOME}#g" \
    "${repo_root}/pai/local_config.example.json" \
    > "${hammerspoon_dir}/pai/local_config.json"
fi

if [[ ! -f "${hammerspoon_dir}/init.lua" ]]; then
  cp "${repo_root}/init-snippet.lua" "${hammerspoon_dir}/init.lua"
  echo "Created ${hammerspoon_dir}/init.lua"
else
  echo "Kept existing ${hammerspoon_dir}/init.lua"
  echo "Add this line if the pet does not start automatically:"
  echo 'require("pai").start()'
fi

if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.reload()' || true
else
  open -a Hammerspoon || true
fi

echo "Installed Xiaoer Hammerspoon Pet."
