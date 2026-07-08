#!/bin/bash
# 下载/提取 vohive-legacy 镜像所需的二进制资产（幂等，带 sha1 校验）
# 用法: bash scripts/fetch-assets.sh
#
# 注意：本脚本刻意避免使用 bash 4+ 的关联数组（declare -A），
# 以保证在 macOS 默认的 /bin/bash (3.2) 下也能运行。
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p assets

# 6mb 备份的闭源二进制（amd64 + arm64）
# 格式："dest|url|expected_sha1"
BINARIES=(
  "assets/vohive_legacy_amd64|https://github.com/6mb/vohive-release/releases/download/v1.5.5/vohive_v1.5.5-10-gf9eb85d_linux_amd64|7dfe34acbb194e01f3144045a01749bba680089b"
  "assets/vohive_legacy_arm64|https://github.com/6mb/vohive-release/releases/download/v1.5.5/vohive_v1.5.5-10-gf9eb85d_linux_arm64|21cf55988ce5c1b3cb01ee72de273d6887cd283b"
)

for entry in "${BINARIES[@]}"; do
  dest="${entry%%|*}"
  rest="${entry#*|}"
  url="${rest%%|*}"
  expected_sha="${rest##*|}"

  # 幂等：已存在且 sha1 匹配则跳过
  if [ -f "$dest" ]; then
    actual_sha=$(shasum -a 1 "$dest" | awk '{print $1}')
    if [ "$actual_sha" = "$expected_sha" ]; then
      echo "[skip] $dest 已存在且校验通过"
      continue
    fi
  fi

  echo "[fetch] $dest ← $url"
  curl -fsSL "$url" -o "$dest"
  chmod +x "$dest"

  actual_sha=$(shasum -a 1 "$dest" | awk '{print $1}')
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "[错误] sha1 校验失败: $dest"
    echo "  期望: $expected_sha"
    echo "  实际: $actual_sha"
    exit 1
  fi
  echo "[ok] $dest ($actual_sha)"
done

# mcc-mnc-table.json：从 ref/dji-4g-vohive-mac 的 backup tarball 提取
MCC_DEST="assets/mcc-mnc-table.json"
if [ -f "$MCC_DEST" ]; then
  echo "[skip] $MCC_DEST 已存在"
else
  echo "[extract] $MCC_DEST ← ref/dji-4g-vohive-mac/vohive-backup.tar.gz"
  BACKUP="ref/dji-4g-vohive-mac/vohive-backup.tar.gz"
  if [ ! -f "$BACKUP" ]; then
    echo "[错误] 找不到 $BACKUP（请确认 submodule 已初始化）"
    exit 1
  fi
  tmpdir=$(mktemp -d)
  tar -xzf "$BACKUP" -C "$tmpdir"
  cp "$tmpdir/vohive-backup/mcc-mnc-table.json" "$MCC_DEST"
  rm -rf "$tmpdir"
  echo "[ok] $MCC_DEST ($(wc -c < "$MCC_DEST" | tr -d ' ') bytes)"
fi

echo ""
echo "全部 assets 就绪："
ls -lh assets/
