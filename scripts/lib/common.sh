#!/bin/bash
# setup.sh / vm-init.sh 共用的辅助函数
set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { printf "${CYAN}[vohive]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[ok]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()  { printf "${RED}[错误]${NC} %s\n" "$*" >&2; }

# 检查命令是否存在
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 1; }
}

# 检查是否 root（VM 内用）
require_root() {
  [ "$(id -u)" -eq 0 ] || { err "需要 root 权限运行"; exit 1; }
}
