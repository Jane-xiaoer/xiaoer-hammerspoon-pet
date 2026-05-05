#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${repo_root}/dist"
stage_dir="${dist_dir}/XiaoerPet"
dmg_path="${dist_dir}/XiaoerPet.dmg"

rm -rf "${stage_dir}" "${dmg_path}"
mkdir -p "${stage_dir}" "${dist_dir}"

copy_item() {
  local item="$1"
  rsync -a --exclude '.DS_Store' "${repo_root}/${item}" "${stage_dir}/"
}

copy_item "Install Xiaoer Pet.command"
copy_item "Switch Pet.command"
copy_item "README.md"
copy_item "README.zh-CN.md"
copy_item "LICENSE"
copy_item "init-snippet.lua"
copy_item "assets"
copy_item "pai"
copy_item "pets"
copy_item "scripts"

chmod +x "${stage_dir}/Install Xiaoer Pet.command"
chmod +x "${stage_dir}/Switch Pet.command"
chmod +x "${stage_dir}/scripts/"*.sh

if [[ -x "${stage_dir}/scripts/apply-command-icon.sh" ]]; then
  "${stage_dir}/scripts/apply-command-icon.sh" "${stage_dir}/assets/xiaoer-ear-install-icon.png" "${stage_dir}/Install Xiaoer Pet.command" || true
  "${stage_dir}/scripts/apply-command-icon.sh" "${stage_dir}/assets/xiaoer-ear-install-icon.png" "${stage_dir}/Switch Pet.command" || true
fi

hdiutil create \
  -volname "Xiaoer Pet" \
  -srcfolder "${stage_dir}" \
  -ov \
  -format UDZO \
  "${dmg_path}"

echo "Built ${dmg_path}"
