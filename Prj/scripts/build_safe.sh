#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prj_dir="$(cd "$script_dir/.." && pwd)"
repo_dir="$(cd "$prj_dir/.." && pwd)"
safe_parent="$repo_dir/build/safe"
safe_repo="$safe_parent/ad9173_ad6688_safe_${USER:-qian}_$$"
build_root="$safe_repo/build/vivado/ad9173_ad6688"
vivado_bin="/home/qian/toolchains/amd/Vivado/2025.1/2025.1/Vivado/bin/vivado"

mkdir -p "$safe_repo"

rsync -a --delete \
  --exclude '.git' \
  --exclude '.Xil' \
  --exclude 'build' \
  --exclude 'Prj/build' \
  "$repo_dir/" "$safe_repo/"

cd "$safe_repo/Prj/scripts"
export KU5P_BUILD_ROOT="$build_root"
exec "$vivado_bin" -mode batch -source build.tcl
