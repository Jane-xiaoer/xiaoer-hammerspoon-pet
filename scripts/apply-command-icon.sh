#!/usr/bin/env bash
set -euo pipefail

icon_path="${1:-}"
target_path="${2:-}"

if [[ -z "${icon_path}" || -z "${target_path}" ]]; then
  exit 0
fi

if [[ ! -f "${icon_path}" || ! -e "${target_path}" ]]; then
  exit 0
fi

icon_abs="$(cd "$(dirname "${icon_path}")" && pwd)/$(basename "${icon_path}")"
target_abs="$(cd "$(dirname "${target_path}")" && pwd)/$(basename "${target_path}")"

script_file="$(mktemp "${TMPDIR:-/tmp}/xiaoer-icon.XXXXXX.applescript")"
trap 'rm -f "${script_file}"' EXIT
cat > "${script_file}" <<'OSA'
use framework "AppKit"
use scripting additions

on run argv
  set iconPath to item 1 of argv
  set targetPath to item 2 of argv
  set image to current application's NSImage's alloc()'s initWithContentsOfFile:iconPath
  if image is missing value then return
  current application's NSWorkspace's sharedWorkspace()'s setIcon:image forFile:targetPath options:0
end run
OSA

osascript "${script_file}" "$icon_abs" "$target_abs"
