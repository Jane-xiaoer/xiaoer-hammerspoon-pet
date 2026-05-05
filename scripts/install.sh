#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hammerspoon_dir="${HOME}/.hammerspoon"
config_path="${hammerspoon_dir}/pai/local_config.json"

prompt_owner_name() {
  local name=""
  if command -v osascript >/dev/null 2>&1; then
    name="$(osascript <<'OSA' || true
try
  set answer to text returned of (display dialog "桌宠怎么称呼你？" default answer "小耳" buttons {"OK"} default button "OK" with title "Xiaoer Pet")
on error
  return ""
end try
return answer
OSA
)"
  elif [[ -t 0 ]]; then
    printf "桌宠怎么称呼你？ [小耳]: "
    IFS= read -r name || name=""
  fi

  if [[ -z "${name//[[:space:]]/}" ]]; then
    name="小耳"
  fi
  printf '%s\n' "${name}"
}

mkdir -p "${hammerspoon_dir}"
rsync -a --delete "${repo_root}/pai/" "${hammerspoon_dir}/pai/"

if [[ -d "${repo_root}/pets" ]]; then
  mkdir -p "${hammerspoon_dir}/pai/pets"
  rsync -a --delete "${repo_root}/pets/" "${hammerspoon_dir}/pai/pets/"
fi

if [[ ! -f "${hammerspoon_dir}/pai/local_config.json" ]]; then
  sed "s#/Users/YOUR_NAME#${HOME}#g" \
    "${repo_root}/pai/local_config.example.json" \
    > "${hammerspoon_dir}/pai/local_config.json"
fi

needs_owner_name="$(python3 - "${config_path}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    data = {}

name = data.get("companion_owner_name")
print("yes" if not isinstance(name, str) or not name.strip() else "no")
PY
)"

if [[ "${needs_owner_name}" == "yes" ]]; then
  owner_name="$(prompt_owner_name)"
  python3 - "${config_path}" "${owner_name}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
owner_name = (sys.argv[2] or "小耳").strip() or "小耳"

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    data = {}

data["companion_owner_name"] = owner_name
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  echo "Companion name set to: ${owner_name}"
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
