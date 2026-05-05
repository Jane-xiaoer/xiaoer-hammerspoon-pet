#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hammerspoon_dir="${HOME}/.hammerspoon"
target_pets_dir="${hammerspoon_dir}/pai/pets"
config_path="${hammerspoon_dir}/pai/local_config.json"

choose_pet_folder() {
  if [[ $# -gt 0 && -n "${1:-}" ]]; then
    printf '%s\n' "$1"
    return
  fi

  osascript <<'OSA'
set defaultPath to POSIX file (POSIX path of (path to home folder) & ".hammerspoon/pai/pets")
try
  set chosenFolder to choose folder with prompt "Choose a Xiaoer pet folder. Pick a folder that contains idle, working, eating, sleeping, etc." default location defaultPath
on error
  return ""
end try
return POSIX path of chosenFolder
OSA
}

selected="$(choose_pet_folder "${1:-}")"
if [[ -z "${selected}" ]]; then
  echo "No pet folder selected."
  exit 1
fi

selected="${selected%/}"
if [[ ! -d "${selected}" ]]; then
  echo "Pet folder does not exist: ${selected}"
  exit 1
fi

required=(idle working eating drinking sleeping failed jumping running-right running-left)
missing=()
for state in "${required[@]}"; do
  if [[ ! -d "${selected}/${state}" ]]; then
    missing+=("${state}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "This folder is missing required state directories:"
  printf '  - %s\n' "${missing[@]}"
  echo
  echo "Use pets/_template as the folder structure reference."
  exit 1
fi

mkdir -p "${target_pets_dir}"
pet_name="$(basename "${selected}")"
if [[ "${pet_name}" == "_template" ]]; then
  echo "Please choose a real pet folder, not pets/_template."
  exit 1
fi

target="${target_pets_dir}/${pet_name}"
rsync -a --delete "${selected}/" "${target}/"

if [[ ! -f "${config_path}" ]]; then
  if [[ -f "${repo_root}/pai/local_config.example.json" ]]; then
    sed "s#/Users/YOUR_NAME#${HOME}#g" "${repo_root}/pai/local_config.example.json" > "${config_path}"
  else
    mkdir -p "$(dirname "${config_path}")"
    printf '{}\n' > "${config_path}"
  fi
fi

python3 - "$config_path" "$target" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
pet_root = pathlib.Path(sys.argv[2])

try:
    data = json.loads(config_path.read_text(encoding="utf-8"))
except Exception:
    data = {}

data["companion_animation_root"] = str(pet_root)
data.setdefault("companion_animation_mood_map", {
    "idle": "idle",
    "focus": "working",
    "break": "waving",
    "hungry": "eating",
    "sleepy": "sleeping",
    "thirsty": "drinking",
})
data.setdefault("companion_idle_animation_cycle_seconds", 600)
data.setdefault("companion_idle_animation_cycle_states", [
    "idle",
    "review",
    "waving",
    "running",
    "waiting",
])

config_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "Switched Xiaoer Pet to: ${pet_name}"
echo "Installed pet folder: ${target}"

if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.reload()' || true
else
  open -a Hammerspoon || true
fi
