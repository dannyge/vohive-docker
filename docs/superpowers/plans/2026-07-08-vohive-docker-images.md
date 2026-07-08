# VoHive Docker 镜像与部署方案 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 openvohive（源码）、vohive-legacy（闭源二进制）、dji2quectel（改 USB 身份工具）三个 Docker 镜像 + macOS OrbStack 一键部署脚本。

**Architecture:** 三个独立镜像共享 assets/ 二进制资产和 docker-bake.hcl 多架构编排；dji2quectel 以纯 shell 脚本为主形态、镜像为辅；macOS 场景用 setup.sh + vm-init.sh 编排 OrbStack Linux VM（类比 Vagrant 的 up/provision）。所有外部依赖（openvohive 源码、两个 ref 仓库）以 git submodule 引入。

**Tech Stack:** Docker buildx（多架构 alpine 镜像）、Go 1.26 + Bun（openvohive 源码构建）、shell（dji2quectel.sh / setup.sh / vm-init.sh）、OrbStack CLI（macOS VM 编排）

**对应 Spec:** `docs/superpowers/specs/2026-07-08-vohive-docker-images-design.md`

---

## 文件结构总览

实施将创建/修改以下文件。按依赖关系排序，每个 Task 产出自包含、可独立测试的变更。

| 文件 | 职责 | 所在 Task |
|---|---|---|
| `.gitignore` | 忽略 assets 下载产物、二进制、临时文件 | Task 1 |
| `.gitmodules` | 记录 3 个 submodule（由 git submodule add 自动生成） | Task 2 |
| `ref/vohive-release/` | submodule → iniwex5/vohive-release | Task 2 |
| `ref/dji-4g-vohive-mac/` | submodule → wlzh/dji-4g-vohive-mac | Task 2 |
| `openvohive/src/` | submodule → openvohive/openvohive | Task 2 |
| `assets/vohive_legacy_amd64` | 6mb 备份的闭源 amd64 二进制 | Task 3 |
| `assets/vohive_legacy_arm64` | 6mb 备份的闭源 arm64 二进制 | Task 3 |
| `assets/mcc-mnc-table.json` | 从 backup 包提取的运营商表 | Task 3 |
| `scripts/fetch-assets.sh` | 下载/提取 assets 的脚本（幂等、带 sha1 校验） | Task 3 |
| `dji2quectel/dji2quectel.sh` | ★ 大疆→移远改身份脚本（主形态） | Task 4 |
| `dji2quectel/Dockerfile` | dji2quectel 镜像（COPY 同一脚本） | Task 4 |
| `dji2quectel/README.md` | dji2quectel 用法 | Task 4 |
| `vohive-legacy/config.template.yaml` | 全字段 config 模板 | Task 5 |
| `vohive-legacy/docker-entrypoint.sh` | env 渲染 yaml + 随机密码 | Task 5 |
| `vohive-legacy/Dockerfile` | 单阶段，ARG TARGETARCH 选二进制 | Task 5 |
| `openvohive/config.example.yaml` | 最小骨架（让 ReadInConfig 不报错） | Task 6 |
| `openvohive/docker-entrypoint.sh` | PROXY_* env 透传 + 随机密码 | Task 6 |
| `openvohive/Dockerfile` | 多阶段：frontend→backend→runtime | Task 6 |
| `openvohive/.dockerignore` | 排除源码仓库的 git/缓存 | Task 6 |
| `docker-bake.hcl` | 三镜像多架构编排 | Task 7 |
| `scripts/setup.sh` | Mac 端 OrbStack 编排 | Task 8 |
| `scripts/vm-init.sh` | VM 内部初始化 | Task 8 |
| `scripts/lib/common.sh` | setup 辅助函数 | Task 8 |
| `docker-compose.yml` | 原生 Linux 示例 | Task 9 |
| `README.md` | 项目总说明 | Task 9 |

---

## Task 1: 仓库初始化

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: git init 工作区**

```bash
cd /Users/dannyge/dev/github/vohive
git init
git config user.name "dannyge"
git config user.email "dannyge@users.noreply.github.com"
```

Expected: `Initialized empty Git repository in /Users/dannyge/dev/github/vohive/.git/`

- [ ] **Step 2: 创建 .gitignore**

Create `.gitignore`:

```gitignore
# ref/ 下已有内容（当前是手动 clone 的），git submodule add 时会被接管，先不忽略
# 但 submodule 的 .git 数据和临时构建产物要忽略

# 临时构建产物
*.tmp
*.bak

# assets 下载脚本产生的临时文件
/tmp/

# macOS
.DS_Store

# IDE
.idea/
.vscode/
*.swp

# 不忽略 assets/ 本身（二进制需进仓库，因为是构建依赖且来源第三方可能消失）
# 不忽略 docs/ ref/ openvohive/ vohive-legacy/ dji2quectel/ scripts/
```

- [ ] **Step 3: 首次提交（仅当前已存在的 docs 和 ref 的占位）**

注意：`ref/` 下当前是手动 clone 的普通目录（含各自的 .git），submodule 化前不能直接 git add（会嵌套）。本步只提交 docs 和 .gitignore，ref 在 Task 2 处理。

```bash
git add .gitignore docs/
git commit -m "chore: init repo with design spec"
```

Expected: 首个 commit 成功，含 .gitignore 和 docs/。

- [ ] **Step 4: 验证 git 状态**

```bash
git status
git log --oneline
```

Expected: `nothing to commit, working tree clean`；log 显示 1 个 commit。

---

## Task 2: 引入 git submodule

**Files:**
- Create: `.gitmodules`（由 git submodule add 自动生成）
- Modify: `ref/vohive-release/`、`ref/dji-4g-vohive-mac/`（从普通目录转为 submodule）
- Create: `openvohive/src/`（submodule）

**前置条件**：`ref/vohive-release/` 和 `ref/dji-4g-vohive-mac/` 当前是手动 clone 的目录，含自己的 `.git`。要先移除它们才能 submodule add。

- [ ] **Step 1: 移除 ref 下手动 clone 的目录（保留远程 URL 记录）**

先确认远程 URL（已知，记录在此供核对）：
- `ref/vohive-release` → `https://github.com/iniwex5/vohive-release.git`
- `ref/dji-4g-vohive-mac` → `https://github.com/wlzh/dji-4g-vohive-mac.git`

```bash
cd /Users/dannyge/dev/github/vohive
rm -rf ref/vohive-release ref/dji-4g-vohive-mac
```

Expected: ref/ 下清空（或只剩 ref 目录本身）。

- [ ] **Step 2: submodule add vohive-release（pin v1.5.5）**

```bash
cd /Users/dannyge/dev/github/vohive
git submodule add https://github.com/iniwex5/vohive-release.git ref/vohive-release
cd ref/vohive-release
git checkout v1.5.5
cd ../..
```

Expected: `ref/vohive-release` 作为 submodule 加入，检出到 tag v1.5.5。`.gitmodules` 自动生成。

- [ ] **Step 3: submodule add dji-4g-vohive-mac（pin main）**

```bash
cd /Users/dannyge/dev/github/vohive
git submodule add https://github.com/wlzh/dji-4g-vohive-mac.git ref/dji-4g-vohive-mac
```

Expected: `ref/dji-4g-vohive-mac` 作为 submodule 加入（默认 main 分支 HEAD）。

- [ ] **Step 4: submodule add openvohive（pin commit 951727cea2db）**

```bash
cd /Users/dannyge/dev/github/vohive
git submodule add https://github.com/openvohive/openvohive.git openvohive/src
cd openvohive/src
git checkout 951727cea2db
cd ../..
```

Expected: `openvohive/src` 作为 submodule 加入，pin 到指定 commit。

- [ ] **Step 5: 验证 submodule 配置**

```bash
cat .gitmodules
git submodule status
```

Expected: `.gitmodules` 含 3 个条目；`git submodule status` 显示 3 个 submodule，前缀字符为空格或 `+`（非 `-`），commit hash 与预期一致：
- vohive-release: v1.5.5 对应的 commit
- dji-4g-vohive-mac: main HEAD
- openvohive/src: `951727cea2db`

- [ ] **Step 6: 提交 submodule**

```bash
git add .gitmodules ref/ openvohive/src
git commit -m "chore: add git submodules (vohive-release, dji-4g-vohive-mac, openvohive)"
```

Expected: commit 成功，含 .gitmodules 和 3 个 submodule 指针。

- [ ] **Step 7: 验证 submodule 可重新初始化**

```bash
cd /Users/dannyge/dev/github/vohive
git submodule update --init --recursive
```

Expected: 无报错（submodules 已就位），输出无新增克隆（因已存在）。

---

## Task 3: 准备 assets 二进制资产

**Files:**
- Create: `scripts/fetch-assets.sh`
- Create: `assets/vohive_legacy_amd64`
- Create: `assets/vohive_legacy_arm64`
- Create: `assets/mcc-mnc-table.json`

这些二进制需进仓库（来源第三方，可能消失）。`scripts/fetch-assets.sh` 是幂等的下载/提取脚本，带 sha1 校验。

**已核实的 sha1（来自 spec 2.3 节）**：
- amd64: `7dfe34acbb194e01f3144045a01749bba680089b`
- arm64: `21cf55988ce5c1b3cb01ee72de273d6887cd283b`

- [ ] **Step 1: 创建 assets 目录**

```bash
mkdir -p /Users/dannyge/dev/github/vohive/assets
```

- [ ] **Step 2: 编写 fetch-assets.sh**

Create `scripts/fetch-assets.sh`:

```bash
#!/bin/bash
# 下载/提取 vohive-legacy 镜像所需的二进制资产（幂等，带 sha1 校验）
# 用法: bash scripts/fetch-assets.sh
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p assets

# 6mb 备份的闭源二进制（amd64 + arm64）
declare -A BINARIES=(
  ["assets/vohive_legacy_amd64"]="https://github.com/6mb/vohive-release/releases/download/v1.5.5/vohive_v1.5.5-10-gf9eb85d_linux_amd64|7dfe34acbb194e01f3144045a01749bba680089b"
  ["assets/vohive_legacy_arm64"]="https://github.com/6mb/vohive-release/releases/download/v1.5.5/vohive_v1.5.5-10-gf9eb85d_linux_arm64|21cf55988ce5c1b3cb01ee72de273d6887cd283b"
)

for dest in "${!BINARIES[@]}"; do
  url="${BINARIES[$dest]%|*}"
  expected_sha="${BINARIES[$dest]#*|}"

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
```

- [ ] **Step 3: 执行 fetch-assets.sh**

```bash
cd /Users/dannyge/dev/github/vohive
chmod +x scripts/fetch-assets.sh
bash scripts/fetch-assets.sh
```

Expected: 3 个文件下载/提取成功，全部 sha1 校验通过，末尾 `ls -lh assets/` 显示：
- `vohive_legacy_amd64` 约 13M
- `vohive_legacy_arm64` 约 11M
- `mcc-mnc-table.json` 约 172K

- [ ] **Step 4: 验证二进制是真实 ELF**

```bash
file assets/vohive_legacy_amd64
file assets/vohive_legacy_arm64
```

Expected:
- `vohive_legacy_amd64: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked`
- `vohive_legacy_arm64: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked`

（不是 "江湖再见" 那种文本）

- [ ] **Step 5: 提交**

```bash
git add scripts/fetch-assets.sh assets/
git commit -m "feat: add legacy binaries and fetch-assets script

- vohive_legacy_amd64 (sha1 7dfe34ac...) from 6mb/vohive-release
- vohive_legacy_arm64 (sha1 21cf5598...) from 6mb/vohive-release
- mcc-mnc-table.json from dji-4g-vohive-mac backup tarball"
```

Expected: commit 成功。

---

## Task 4: dji2quectel 镜像与脚本

**Files:**
- Create: `dji2quectel/dji2quectel.sh`
- Create: `dji2quectel/Dockerfile`
- Create: `dji2quectel/README.md`
- Create: `scripts/dji2quectel.sh`（指向同一份脚本的符号链接或副本）

这是三个交付物中最简单、无二进制依赖的。先做它能快速验证 build 流程。

**spec 依据**：第 6 节。脚本全流程见 spec 6.2，关键决策见 6.3。

- [ ] **Step 1: 编写 dji2quectel.sh**

Create `dji2quectel/dji2quectel.sh`:

```bash
#!/bin/bash
# dji2quectel: 把大疆 4G 模块的 USB 身份永久改写为移远 Quectel EC25
# 改的是模块内部 NV，一次性、终身有效。
#
# 主形态：纯脚本，在 Linux VM/真机内直接 bash 执行
# 镜像形态：docker run（见同目录 Dockerfile）
#
# 环境变量（均可选）：
#   SRC_VIDPID    源 VID:PID，默认 2ca3:4006（大疆）
#   DST_VID       目标 VID，默认 0x2C7C（移远）
#   DST_PID       目标 PID，默认 0x0125（EC25）
#   AT_PORT       手动指定 AT 口（如 /dev/ttyUSB2），默认自动探测
#   WAIT_TIMEOUT  等待重新枚举秒数，默认 30
set -euo pipefail

SRC_VIDPID="${SRC_VIDPID:-2ca3:4006}"
DST_VID="${DST_VID:-0x2C7C}"
DST_PID="${DST_PID:-0x0125}"
AT_PORT="${AT_PORT:-}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"

SRC_VID="${SRC_VIDPID%%:*}"
SRC_PID="${SRC_VIDPID##*:}"
DST_VIDPID_LOWER="$(echo "$DST_VID" | tr '[:upper:]' '[:lower:]'):$(printf '%04x' "0x$DST_PID" 2>/dev/null || echo "$DST_PID" | tr '[:upper:]' '[:lower:]')"

log()  { printf '[dji2quectel] %s\n' "$*"; }
err()  { printf '[dji2quectel] 错误: %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 1; }
}

for c in lsusb socat modprobe; do need_cmd "$c"; done

# ── 1. 检测模块当前身份 ──────────────────────────────────
log "检测 USB 设备..."
if lsusb | grep -qi "$DST_VIDPID_LOWER"; then
  log "模块已是目标身份 ($DST_VIDPID_LOWER)，无需改写。跳过。"
  exit 0
fi

if ! lsusb | grep -qi "$SRC_VIDPID"; then
  err "未检测到大疆模块 ($SRC_VIDPID)。"
  err "请确认模块已通过 USB 直通进入本系统（orb usb attach / UTM 直通）。"
  exit 1
fi

log "检测到大疆模块 ($SRC_VIDPID)，开始改写为 Quectel ($DST_VID:$DST_PID)..."

# ── 2. 加载 USB serial 驱动 ──────────────────────────────
log "加载 option 驱动..."
modprobe option 2>/dev/null || { err "modprobe option 失败（内核可能无此模块）"; exit 1; }

NEW_ID_PATH="/sys/bus/usb-serial/drivers/option1/new_id"
if [ ! -f "$NEW_ID_PATH" ]; then
  err "找不到 $NEW_ID_PATH（option 驱动未正确加载）"
  exit 1
fi

log "注册 VID:PID $SRC_VID $SRC_PID → option 驱动..."
echo "$SRC_VID $SRC_PID" > "$NEW_ID_PATH" || { err "写入 new_id 失败（需要 root/特权）"; exit 1; }

# 等串口节点生成
sleep 2

# ── 3. 探测 AT 口（不写死 ttyUSB2）──────────────────────
find_at_port() {
  if [ -n "$AT_PORT" ]; then
    if [ -e "$AT_PORT" ]; then echo "$AT_PORT"; return 0; fi
    err "指定的 AT_PORT ($AT_PORT) 不存在"
    return 1
  fi
  for dev in /dev/ttyUSB*; do
    [ -e "$dev" ] || continue
    # 试发 AT，收 OK 即为 AT 口
    resp=$(printf 'AT\r' | timeout 3 socat - "$dev,crnl" 2>/dev/null || true)
    if echo "$resp" | grep -qi "OK"; then
      echo "$dev"
      return 0
    fi
  done
  return 1
}

log "探测 AT 口..."
AT_PORT=$(find_at_port) || { err "找不到可响应 AT 的串口（/dev/ttyUSB*）"; exit 1; }
log "AT 口: $AT_PORT"

# ── 4. 发 AT 指令改写 USB 身份 ───────────────────────────
log "发送 AT+QCFG 改写 USB 身份..."
printf 'AT+QCFG="usbcfg",%s,%s,1,1,1,1,1,0,0\r' "$DST_VID" "$DST_PID" | socat - "$AT_PORT,crnl"

# ── 5. 软重启使配置生效 ──────────────────────────────────
log "发送 AT+CFUN=1,1 软重启模块..."
printf 'AT+CFUN=1,1\r' | socat - "$AT_PORT,crnl"

# ── 6. 等待重新枚举 ──────────────────────────────────────
log "等待模块重新枚举为新身份 ($DST_VIDPID_LOWER)，超时 ${WAIT_TIMEOUT}s..."
elapsed=0
while [ "$elapsed" -lt "$WAIT_TIMEOUT" ]; do
  if lsusb | grep -qi "$DST_VIDPID_LOWER"; then
    log "✓ 改写成功！模块现为 Quectel 身份 ($DST_VIDPID_LOWER)"
    log "  lsusb 输出:"
    lsusb | grep -i "$DST_VIDPID_LOWER" | sed 's/^/    /'
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

err "超时：${WAIT_TIMEOUT}s 内未检测到新身份。"
err "可能是软重启后 USB 直通断开——请重新绑定直通后再次运行本脚本。"
exit 1
```

- [ ] **Step 2: 编写 Dockerfile**

Create `dji2quectel/Dockerfile`:

```dockerfile
# dji2quectel: 把大疆 4G 模块改写为移远 Quectel EC25 身份
# 一次性任务容器，运行需 --privileged + 挂载 /sys /lib/modules /dev
FROM alpine:latest

RUN apk add --no-cache socat usbutils kmod bash

COPY dji2quectel.sh /app/dji2quectel.sh
RUN chmod +x /app/dji2quectel.sh

WORKDIR /app
ENTRYPOINT ["/app/dji2quectel.sh"]
```

- [ ] **Step 3: 编写 README**

Create `dji2quectel/README.md`:

````markdown
# dji2quectel

把大疆 4G 模块（本质移远 Quectel EG25-G）的 USB 身份从大疆私有 `2ca3:4006` **永久改写**为移远 EC25 的 `2C7C:0125`，使通用驱动和 VoHive 能识别。改的是模块内部 NV，一次性、终身有效。

## 两种用法

### 1. 纯脚本（VM 内直接运行，推荐）

在 Linux VM 或真机内：
```bash
bash dji2quectel.sh
```

### 2. Docker 镜像（原生 Linux 用户一句 docker run）

```bash
docker run --rm --privileged \
  -v /sys:/sys \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  dji2quectel:latest
```

## 环境变量（可选）

| 变量 | 默认 | 说明 |
|---|---|---|
| `SRC_VIDPID` | `2ca3:4006` | 源身份（大疆） |
| `DST_VID` | `0x2C7C` | 目标 VID（移远） |
| `DST_PID` | `0x0125` | 目标 PID（EC25） |
| `AT_PORT` | 自动探测 | 手动指定 AT 口 |
| `WAIT_TIMEOUT` | `30` | 等待重新枚举秒数 |

## 反向操作（改回大疆身份，基本用不到）

```bash
SRC_VIDPID=2c7c:0125 DST_VID=0x2CA3 DST_PID=0x4006 bash dji2quectel.sh
```

## 特性

- **幂等**：已是 Quectel 身份则直接跳过，重复运行不出错
- **自动探测 AT 口**：遍历 `/dev/ttyUSB*`，不写死 `ttyUSB2`
- **VID:PID 可配置**：支持改写其他模块身份

## 约束

需 Linux 内核 + `option` 驱动。仅能在真实 Linux 主机或 Linux VM（UTM/OrbStack machine）内运行，不能在 macOS 裸机直接 docker run（无 Linux 内核）。
````

- [ ] **Step 4: 创建 scripts/dji2quectel.sh（指向同一份脚本）**

```bash
cd /Users/dannyge/dev/github/vohive
ln -s ../dji2quectel/dji2quectel.sh scripts/dji2quectel.sh
```

验证：
```bash
ls -la scripts/dji2quectel.sh
head -1 scripts/dji2quectel.sh
```

Expected: 符号链接指向 `../dji2quectel/dji2quectel.sh`，内容首行 `#!/bin/bash`。

- [ ] **Step 5: 语法检查脚本**

```bash
cd /Users/dannyge/dev/github/vohive
bash -n dji2quectel/dji2quectel.sh
```

Expected: 无输出（语法正确）。若有语法错误会报 `syntax error`。

- [ ] **Step 6: 本地构建镜像（amd64，验证 Dockerfile 正确）**

```bash
cd /Users/dannyge/dev/github/vohive/dji2quectel
docker build -t dji2quectel:test .
```

Expected: 构建成功，镜像生成。`docker images dji2quectel:test` 能看到。

- [ ] **Step 7: 验证镜像可运行（无设备时应优雅报错退出）**

```bash
docker run --rm dji2quectel:test
```

Expected: 因为没有 USB 设备，脚本应输出 `[dji2quectel] 错误: 未检测到大疆模块 (2ca3:4006)...` 并 `exit 1`（不是崩溃或语法错误）。

- [ ] **Step 8: 提交**

```bash
cd /Users/dannyge/dev/github/vohive
git add dji2quectel/ scripts/dji2quectel.sh
git commit -m "feat: add dji2quectel image and script

- dji2quectel.sh: rewrite DJI 4G module USB identity to Quectel EC25
- idempotent, auto-detect AT port, configurable VID:PID
- Dockerfile for native Linux users (docker run --privileged)"
```

---

## Task 5: vohive-legacy 镜像

**Files:**
- Create: `vohive-legacy/config.template.yaml`
- Create: `vohive-legacy/docker-entrypoint.sh`
- Create: `vohive-legacy/Dockerfile`

**spec 依据**：第 5 节。单阶段 Dockerfile，ARG TARGETARCH 选二进制；entrypoint 从 PROXY_* env 渲染 yaml。

- [ ] **Step 1: 编写 config.template.yaml（全字段模板）**

从 backup 包的 install.sh 提取完整模板（含 telegram/webhook/email/qq/feishu/bark/pushplus）。先查看参考：

```bash
cd /Users/dannyge/dev/github/vohive
# backup 包里的 config 模板在 install.sh 里（Task 3 已提取过 tarball，这里再看一下原文件）
tar -xzf ref/dji-4g-vohive-mac/vohive-backup.tar.gz -O vohive-backup/install.sh 2>/dev/null | sed -n '/cat > "\$CONFIG_PATH"/,/^EOF$/p'
```

参考输出，创建 `vohive-legacy/config.template.yaml`：

```yaml
# vohive-legacy 完整配置模板（所有渠道默认禁用）
# 实际值由 docker-entrypoint.sh 从 PROXY_* 环境变量渲染注入
bark:
  enabled: false
  group: vohive
  icon: ""
  level: active
  urls: []
email:
  enabled: false
  from_address: ""
  password: ""
  smtp_host: ""
  smtp_port: 0
  to_addresses: []
  username: ""
  use_ssl: false
feishu:
  app_id: ""
  app_secret: ""
  chat_ids: []
  enabled: false
pushplus:
  channel: wechat
  enabled: false
  token: ""
  topic: ""
qq:
  app_id: ""
  app_secret: ""
  direct_ids: ""
  enabled: false
  group_ids: ""
server:
  port: ":7575"
telegram:
  admin_id: 0
  base_url: ""
  bot_token: ""
  chat_id: 0
  enabled: false
  proxy: ""
web:
  password: "admin"
  username: admin
webhook:
  enabled: false
  headers: {}
  retry_max: 3
  secret: ""
  text_template: '{{device_label}} {{text}}'
  timeout_ms: 5000
  urls: []
devices: []
```

- [ ] **Step 2: 编写 docker-entrypoint.sh**

Create `vohive-legacy/docker-entrypoint.sh`:

```bash
#!/bin/sh
set -eu

# ── 1. 随机密码（未传 PROXY_WEB_PASSWORD 时每次启动生成）──────────
if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== vohive-legacy 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '  (docker logs 可再次查看；重启会换新密码)\n'
  printf '==========================================\n\n'
  export PROXY_WEB_PASSWORD
fi

# ── 2. 渲染 config.yaml（从 PROXY_* env）──────────────────────────
# 优先使用用户挂载的 config（若存在），否则从 env 渲染
CONFIG_PATH="${VOHIVE_CONFIG:-/app/data/config.yaml}"

if [ "$CONFIG_PATH" = "/app/data/config.yaml" ]; then
  mkdir -p /app/data/logs

  # server.port 处理：vohive 期望 ":7575" 格式
  PORT="${PROXY_SERVER_PORT:-7575}"
  case "$PORT" in
    :*) PORT_YAML="$PORT" ;;
    *)  PORT_YAML=":$PORT" ;;
  esac

  cat > "$CONFIG_PATH" <<EOF
bark:
  enabled: ${PROXY_BARK_ENABLED:-false}
  group: ${PROXY_BARK_GROUP:-vohive}
  urls: ${PROXY_BARK_URLS:-[]}
email:
  enabled: ${PROXY_EMAIL_ENABLED:-false}
  smtp_host: "${PROXY_EMAIL_SMTP_HOST:-}"
  smtp_port: ${PROXY_EMAIL_SMTP_PORT:-0}
  username: "${PROXY_EMAIL_USERNAME:-}"
  password: "${PROXY_EMAIL_PASSWORD:-}"
  from_address: "${PROXY_EMAIL_FROM_ADDRESS:-}"
  to_addresses: ${PROXY_EMAIL_TO_ADDRESSES:-[]}
  use_ssl: ${PROXY_EMAIL_USE_SSL:-false}
feishu:
  enabled: ${PROXY_FEISHU_ENABLED:-false}
  app_id: "${PROXY_FEISHU_APP_ID:-}"
  app_secret: "${PROXY_FEISHU_APP_SECRET:-}"
  chat_ids: ${PROXY_FEISHU_CHAT_IDS:-[]}
pushplus:
  enabled: ${PROXY_PUSHPLUS_ENABLED:-false}
  token: "${PROXY_PUSHPLUS_TOKEN:-}"
  topic: "${PROXY_PUSHPLUS_TOPIC:-}"
  channel: ${PROXY_PUSHPLUS_CHANNEL:-wechat}
qq:
  enabled: ${PROXY_QQ_ENABLED:-false}
  app_id: "${PROXY_QQ_APP_ID:-}"
  app_secret: "${PROXY_QQ_APP_SECRET:-}"
  group_ids: "${PROXY_QQ_GROUP_IDS:-}"
  direct_ids: "${PROXY_QQ_DIRECT_IDS:-}"
server:
  port: "$PORT_YAML"
telegram:
  enabled: ${PROXY_TELEGRAM_ENABLED:-false}
  bot_token: "${PROXY_TELEGRAM_BOT_TOKEN:-}"
  admin_id: ${PROXY_TELEGRAM_ADMIN_ID:-0}
  chat_id: ${PROXY_TELEGRAM_CHAT_ID:-0}
  base_url: "${PROXY_TELEGRAM_BASE_URL:-}"
  proxy: "${PROXY_TELEGRAM_PROXY:-}"
web:
  username: "${PROXY_WEB_USERNAME:-admin}"
  password: "${PROXY_WEB_PASSWORD}"
webhook:
  enabled: ${PROXY_WEBHOOK_ENABLED:-false}
  urls: ${PROXY_WEBHOOK_URLS:-[]}
  secret: "${PROXY_WEBHOOK_SECRET:-}"
  headers: ${PROXY_WEBHOOK_HEADERS:-{}}
  timeout_ms: ${PROXY_WEBHOOK_TIMEOUT_MS:-5000}
  retry_max: ${PROXY_WEBHOOK_RETRY_MAX:-3}
  text_template: "${PROXY_WEBHOOK_TEXT_TEMPLATE:-{{device_label}} {{text}}}"
devices: []
EOF
  chmod 600 "$CONFIG_PATH"
fi

# ── 3. 启动 ──────────────────────────────────────────────
exec /app/vohive -c "$CONFIG_PATH"
```

- [ ] **Step 3: 编写 Dockerfile**

Create `vohive-legacy/Dockerfile`:

```dockerfile
# vohive-legacy: 闭源完整版 vohive v1.5.5（过渡，将淡出）
# 二进制来自 6mb/vohive-release 备份（见 assets/fetch-assets.sh）
# buildx 会按 TARGETARCH 自动注入 amd64/arm64
FROM alpine:latest

ARG TARGETARCH

RUN apk add --no-cache ca-certificates tzdata libc6-compat socat && \
    [ ! -d /usr/share/zoneinfo/Asia ] || cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true

WORKDIR /app

# 按架构选二进制
COPY assets/vohive_legacy_${TARGETARCH} /app/vohive
RUN chmod +x /app/vohive

# 运营商表（完整版需要）
COPY assets/mcc-mnc-table.json /app/data/mcc-mnc-table.json

# 配置模板和入口脚本
COPY vohive-legacy/config.template.yaml /app/config.template.yaml
COPY vohive-legacy/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
```

- [ ] **Step 4: 语法检查 entrypoint**

```bash
cd /Users/dannyge/dev/github/vohive
sh -n vohive-legacy/docker-entrypoint.sh
```

Expected: 无输出（语法正确）。

- [ ] **Step 5: 本地构建镜像（amd64）**

```bash
cd /Users/dannyge/dev/github/vohive
docker build -t vohive-legacy:test -f vohive-legacy/Dockerfile .
```

注意 context 是仓库根（`.`），因为要 COPY assets/。

Expected: 构建成功。

- [ ] **Step 6: 验证镜像启动 + 随机密码打印**

```bash
docker run --rm vohive-legacy:test
```

Expected: 打印密码框（`======== vohive-legacy 未配置密码 ========` 含用户名和随机密码）。随后 vohive 二进制尝试启动——因无 config 设备/网络，可能报错退出或卡住，这正常（本步只验证 entrypoint 渲染逻辑和二进制能加载）。若想只验证渲染不启动，可临时改 entrypoint：

```bash
docker run --rm --entrypoint cat vohive-legacy:test /app/data/config.yaml
```

Expected: 输出渲染好的 config.yaml，含 `password: <随机串>`，`username: admin`。

- [ ] **Step 7: 验证传入密码时不打印随机密码**

```bash
docker run --rm --entrypoint cat -e PROXY_WEB_PASSWORD=mypass123 vohive-legacy:test /app/data/config.yaml | grep password
```

Expected: 输出 `password: mypass123`（用的是传入值，无随机密码框）。

- [ ] **Step 8: 提交**

```bash
cd /Users/dannyge/dev/github/vohive
git add vohive-legacy/
git commit -m "feat: add vohive-legacy image (closed-source v1.5.5)

- single-stage Dockerfile, ARG TARGETARCH selects prebuilt binary
- entrypoint renders full config.yaml from PROXY_* env
- random password generation when PROXY_WEB_PASSWORD unset"
```

---

## Task 6: openvohive 镜像

**Files:**
- Create: `openvohive/config.example.yaml`
- Create: `openvohive/docker-entrypoint.sh`
- Create: `openvohive/.dockerignore`
- Create: `openvohive/Dockerfile`

**spec 依据**：第 4 节。多阶段构建（frontend→backend→runtime）；config 走 viper 原生 PROXY_* env；entrypoint 极简（viper 自动处理 env），只做随机密码。

**源码位置**：`openvohive/src/`（Task 2 已作为 submodule 加入）。

- [ ] **Step 1: 确认 submodule 源码结构**

```bash
cd /Users/dannyge/dev/github/vohive
ls openvohive/src/
cat openvohive/src/go.mod | head -5
```

Expected: 看到完整源码结构（main.go, go.mod, web/, internal/, pkg/ 等），go.mod 显示 `go 1.26.3`。

- [ ] **Step 2: 编写 config.example.yaml（最小骨架）**

openvohive 用 viper，`ReadInConfig()` 要求文件存在。这个骨架让它在没挂载自定义配置时也能启动，实际值靠 PROXY_* env 覆盖。

Create `openvohive/config.example.yaml`:

```yaml
# openvohive 最小配置骨架
# 实际值由 PROXY_* 环境变量覆盖（viper AutomaticEnv）
# 仅用于满足 viper ReadInConfig() 的文件存在要求
server:
  port: 7575
  debug: false
web:
  username: admin
  password: admin
devices: []
```

- [ ] **Step 3: 编写 docker-entrypoint.sh**

Create `openvohive/docker-entrypoint.sh`:

```bash
#!/bin/sh
set -eu

# ── 随机密码（未传 PROXY_WEB_PASSWORD 时每次启动生成）──────────
if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== openvohive 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '  (docker logs 可再次查看；重启会换新密码)\n'
  printf '=======================================\n\n'
  export PROXY_WEB_PASSWORD
fi

# ── 配置路径：默认内置骨架，用户可挂载自定义覆盖 ─────────────────
CONFIG="${VOHIVE_CONFIG:-/app/config/config.yaml}"

# ── 数据/日志目录 ─────────────────────────────────────────
mkdir -p /app/data/logs

# ── 启动（viper AutomaticEnv 自动读取 PROXY_* 环境变量）────
exec /app/server -c "$CONFIG" ${VOHIVE_ARGS:-}
```

- [ ] **Step 4: 编写 .dockerignore**

Create `openvohive/.dockerignore`（排除 submodule 源码里的无关文件，减小构建上下文）:

```gitignore
# 排除 openvohive/src 里的无关文件（减小构建上下文）
openvohive/src/.git
openvohive/src/.github
**/*.log
**/*.db
**/*.sqlite*
**/.DS_Store

# 排除我们自己的构建产物
*.tmp
```

> 注意：此 `.dockerignore` 作用于仓库根 context（因 bake 的 openvohive target context = `.`）。路径要带 `openvohive/src/` 前缀。

- [ ] **Step 5: 编写 Dockerfile（多阶段）**

Create `openvohive/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.4
# openvohive: 开源版 vohive（聚焦短信收发/转发）
# 多阶段构建：前端(Vue/Bun) → 后端(Go) → 运行时(Alpine)
# 源码来自 openvohive/src/ git submodule

# ── Stage 1: 前端构建 ──────────────────────────────────────
FROM oven/bun:1-alpine AS frontend

WORKDIR /build
# 只拷 web 目录，利用缓存
COPY openvohive/src/web/package.json openvohive/src/web/bun.lock* ./web/
RUN cd web && bun install --frozen-lockfile || bun install

COPY openvohive/src/web/ ./web/
COPY openvohive/src/web/embed.go openvohive/src/web/generate.go ./web/
RUN cd web && bun run build

# ── Stage 2: 后端构建 ──────────────────────────────────────
FROM golang:1.26-alpine AS backend

RUN apk add --no-cache git

WORKDIR /build
# 拷贝完整源码
COPY openvohive/src/ ./
# 拷入前端构建产物（go:embed 需要 dist 在位）
COPY --from=frontend /build/web/dist ./web/dist

RUN go generate ./...
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" -trimpath \
    -o /out/server .

# ── Stage 3: 运行时 ────────────────────────────────────────
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata libc6-compat socat && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true

WORKDIR /app

COPY --from=backend /out/server /app/server
RUN chmod +x /app/server

COPY openvohive/config.example.yaml /app/config/config.yaml
COPY openvohive/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
```

- [ ] **Step 6: 语法检查 entrypoint**

```bash
cd /Users/dannyge/dev/github/vohive
sh -n openvohive/docker-entrypoint.sh
```

Expected: 无输出。

- [ ] **Step 7: 本地构建镜像（amd64，验证多阶段构建走通）**

```bash
cd /Users/dannyge/dev/github/vohive
docker build -t openvohive:test -f openvohive/Dockerfile .
```

Expected: 构建成功（三个 stage 都过）。首次会下载 bun、golang 镜像和 go modules，耗时较长。

> 若 `bun install --frozen-lockfile` 因 lockfile 不匹配失败，fallback 到 `bun install`（Dockerfile 已写 `|| bun install`）。

- [ ] **Step 8: 验证镜像启动 + 随机密码**

```bash
docker run --rm openvohive:test
```

Expected: 打印密码框。随后 openvohive server 启动（可能因无设备/数据库初始化而日志若干，但应能 listen 在 :7575 或打印启动日志）。

- [ ] **Step 9: 验证传入密码 + 后台可访问（快速冒烟）**

```bash
# 后台启动
docker run -d -p 7575:7575 -e PROXY_WEB_PASSWORD=testpass123 --name vohive-smoke openvohive:test
sleep 3
# 探测端口
curl -sS -o /dev/null -w "%{http_code}" http://localhost:7575/ || echo "连接失败"
# 清理
docker rm -f vohive-smoke
```

Expected: curl 返回 HTTP 状态码（如 200/302/401，取决于 openvohive 的路由）。能连上即说明启动成功。

- [ ] **Step 10: 提交**

```bash
cd /Users/dannyge/dev/github/vohive
git add openvohive/config.example.yaml openvohive/docker-entrypoint.sh openvohive/.dockerignore openvohive/Dockerfile
git commit -m "feat: add openvohive image (open-source, source build)

- multi-stage Dockerfile: bun frontend → go backend → alpine runtime
- source from openvohive/src submodule
- config via viper native PROXY_* env (no yaml rendering needed)
- random password generation when PROXY_WEB_PASSWORD unset"
```

---

## Task 7: 多架构构建编排（docker-bake.hcl）

**Files:**
- Create: `docker-bake.hcl`

**spec 依据**：第 8 节。

- [ ] **Step 1: 编写 docker-bake.hcl**

Create `docker-bake.hcl`:

```hcl
# docker buildx bake 多架构构建编排
# 用法:
#   docker buildx bake --load      # 本地加载（单架构时）
#   docker buildx bake --push      # 推送到 registry（需先 docker login）
#   docker buildx bake openvohive  # 只构建单个 target

group "default" {
  targets = ["openvohive", "vohive-legacy", "dji2quectel"]
}

variable "REGISTRY" {
  default = ""
}

target "openvohive" {
  context    = "."
  dockerfile = "openvohive/Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = compact([
    "openvohive:latest",
    REGISTRY != "" ? "${REGISTRY}/openvohive:latest" : "",
  ])
}

target "vohive-legacy" {
  context    = "."
  dockerfile = "vohive-legacy/Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = compact([
    "vohive-legacy:latest",
    REGISTRY != "" ? "${REGISTRY}/vohive-legacy:latest" : "",
  ])
}

target "dji2quectel" {
  context    = "./dji2quectel"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = compact([
    "dji2quectel:latest",
    REGISTRY != "" ? "${REGISTRY}/dji2quectel:latest" : "",
  ])
}
```

- [ ] **Step 2: 验证 bake 配置语法**

```bash
cd /Users/dannyge/dev/github/vohive
docker buildx bake --print default
```

Expected: 输出 JSON 格式的构建计划，含 3 个 target，每个有 platforms `["linux/amd64","linux/arm64"]`。无报错。

- [ ] **Step 3: 本地构建验证（amd64 单架构，快速冒烟）**

确保 buildx builder 存在：
```bash
docker buildx ls
```
若无 builder，创建：
```bash
docker buildx create --use --name vohive-builder
```

构建（用 `--load` 只能单架构，先验证 amd64）：
```bash
cd /Users/dannyge/dev/github/vohive
docker buildx bake --load --set *.platform=linux/amd64 default
```

Expected: 3 个镜像都构建成功并加载到本地。`docker images | grep -E "openvohive|vohive-legacy|dji2quectel"` 能看到。

- [ ] **Step 4: 提交**

```bash
cd /Users/dannyge/dev/github/vohive
git add docker-bake.hcl
git commit -m "feat: add docker-bake.hcl for multi-arch builds"
```

---

## Task 8: macOS 部署编排脚本

**Files:**
- Create: `scripts/lib/common.sh`
- Create: `scripts/vm-init.sh`
- Create: `scripts/setup.sh`

**spec 依据**：第 7 节。setup.sh 在 Mac 端编排 OrbStack；vm-init.sh 在 VM 内部执行。

- [ ] **Step 1: 编写 scripts/lib/common.sh（辅助函数）**

Create `scripts/lib/common.sh`:

```bash
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
```

- [ ] **Step 2: 编写 scripts/vm-init.sh（VM 内部执行）**

这个脚本在 OrbStack VM 内运行：装 docker、改身份、起平台镜像。由 setup.sh 通过 `orb push` 推入后执行。

Create `scripts/vm-init.sh`:

```bash
#!/bin/bash
# vm-init.sh: 在 OrbStack Linux VM 内部执行
# 由 setup.sh 推入 VM 后运行（orb push + orb -m <vm> bash）
# 职责：装 docker → 改 USB 身份 → 起 openvohive 容器
set -euo pipefail

# 加载辅助函数（与 setup.sh 共用同一份）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || . /tmp/lib/common.sh

require_root

VM_NAME="${VOHIVE_VM_NAME:-vohive}"
IMAGE="${VOHIVE_IMAGE:-openvohive:latest}"
DATA_DIR="/opt/vohive/data"

# ── 1. 安装 Docker（若未装）──────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  log "安装 Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl socat usbutils
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
  ok "Docker 已安装并启动"
else
  ok "Docker 已存在，跳过安装"
fi

# ── 2. 改 USB 身份（幂等）────────────────────────────────
# dji2quectel.sh 由 setup.sh 一并推入 /tmp/
if [ -f /tmp/dji2quectel.sh ]; then
  log "执行 USB 身份改写（幂等，已是 Quectel 则跳过）..."
  bash /tmp/dji2quectel.sh || warn "改写未完成或需要重新绑定 USB 直通后重试"
fi

# ── 3. 加载镜像（若 VM 内无）────────────────────────────
# setup.sh 会 docker save 推入 /tmp/*.tar，这里 load
for tarball in /tmp/openvohive.tar /tmp/vohive-legacy.tar; do
  [ -f "$tarball" ] || continue
  log "加载镜像: $tarball"
  docker load -i "$tarball" && rm -f "$tarball"
done

# ── 4. 启动平台容器（幂等）──────────────────────────────
CONTAINER="${VOHIVE_CONTAINER:-vohive}"
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    ok "容器 $CONTAINER 已在运行，跳过"
  else
    warn "容器 $CONTAINER 已存在但未运行，启动之"
    docker start "$CONTAINER"
  fi
else
  log "启动 $CONTAINER 容器..."
  mkdir -p "$DATA_DIR"
  # 透传 PROXY_* 环境变量（setup.sh 已 export 或用户预设）
  docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    --privileged \
    -v /dev:/dev \
    -v "$DATA_DIR":/app/data \
    -p 7575:7575 \
    $(env | grep '^PROXY_' | sed 's/^/-e /') \
    "$IMAGE"
  ok "容器 $CONTAINER 已启动"
fi

# ── 5. 输出访问信息 ─────────────────────────────────────
VM_IP=$(hostname -I | awk '{print $1}')
ok "部署完成！"
printf "\n"
printf "  后台地址: http://%s:7575\n" "$VM_IP"
printf "  查看密码: docker logs %s | grep 密码\n" "$CONTAINER"
printf "  （未传 PROXY_WEB_PASSWORD 时每次启动生成随机密码）\n\n"
```

- [ ] **Step 3: 编写 scripts/setup.sh（Mac 端主编排）**

Create `scripts/setup.sh`:

```bash
#!/bin/bash
# setup.sh: macOS 上一键部署 vohive
# 流程: 检查 OrbStack → 建 VM → USB 直通 → 推送脚本/镜像 → VM 内初始化
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

VM_NAME="${VOHIVE_VM_NAME:-vohive}"
VM_IMAGE="${VOHIVE_VM_IMAGE:-ubuntu:24.04}"
PLATFORM_IMAGE="${VOHIVE_IMAGE:-openvohive:latest}"

# ── 1. 检查 OrbStack ────────────────────────────────────
log "检查 OrbStack..."
if ! command -v orb >/dev/null 2>&1; then
  warn "未检测到 OrbStack。安装中..."
  need_cmd brew
  brew install --cask orbstack
  err "OrbStack 已安装。请先启动 OrbStack 应用并完成首次授权，然后重新运行本脚本。"
  exit 1
fi
ok "OrbStack 已就绪"

# ── 2. 创建 VM（幂等）───────────────────────────────────
if orb list 2>/dev/null | grep -qw "$VM_NAME"; then
  ok "VM '$VM_NAME' 已存在，跳过创建"
else
  log "创建 VM '$VM_NAME'（镜像 $VM_IMAGE）..."
  orb create "$VM_IMAGE" "$VM_NAME"
  ok "VM 已创建"
fi

# 确保 VM 运行
orb -m "$VM_NAME" start 2>/dev/null || true
log "等待 VM 就绪..."
for i in $(seq 1 30); do
  if orb -m "$VM_NAME" true >/dev/null 2>&1; then
    ok "VM 已就绪"
    break
  fi
  sleep 2
  [ "$i" -eq 30 ] && { err "VM 启动超时"; exit 1; }
done

# ── 3. USB 直通 ─────────────────────────────────────────
log "检测大疆 4G 模块（VID:PID 2ca3:4006 或已改写的 2c7c:0125）..."
SRC_DEV=""
DST_DEV=""
# orb usb list 输出格式各异，尝试匹配
SRC_DEV=$(orb usb list 2>/dev/null | grep -i "2ca3:4006" | awk '{print $1}' | head -1 || true)
DST_DEV=$(orb usb list 2>/dev/null | grep -i "2c7c:0125" | awk '{print $1}' | head -1 || true)

if [ -n "$DST_DEV" ]; then
  ok "模块已是 Quectel 身份（2c7c:0125），直通到 VM"
  orb usb attach "$DST_DEV" "$VM_NAME" 2>/dev/null || warn "直通可能已绑定"
elif [ -n "$SRC_DEV" ]; then
  ok "检测到大疆模块，直通到 VM（改身份会触发重新枚举，稍后需重绑）"
  orb usb attach "$SRC_DEV" "$VM_NAME" 2>/dev/null || warn "直通可能已绑定"
else
  warn "未检测到大疆模块（2ca3:4006 / 2c7c:0125）"
  warn "请插入模块后继续，或按 Ctrl+C 取消"
  printf "  按回车继续（跳过 USB 直通，仅部署平台）..."
  read -r
fi

# ── 4. 构建或确认平台镜像存在 ───────────────────────────
log "检查平台镜像 $PLATFORM_IMAGE..."
if ! docker image inspect "$PLATFORM_IMAGE" >/dev/null 2>&1; then
  warn "本地无 $PLATFORM_IMAGE，开始构建..."
  cd "$PROJECT_ROOT"
  docker buildx bake --load --set *.platform=linux/$(uname -m | sed 's/x86_64/amd64/;s/arm64/arm64/') openvohive
  cd "$SCRIPT_DIR"
fi
ok "平台镜像就绪"

# ── 5. 传输脚本和镜像到 VM ──────────────────────────────
log "传输部署脚本到 VM..."
orb push "$VM_NAME" "$SCRIPT_DIR/vm-init.sh" /tmp/vm-init.sh
orb push "$VM_NAME" "$SCRIPT_DIR/lib/common.sh" /tmp/lib/common.sh
orb push "$VM_NAME" "$PROJECT_ROOT/dji2quectel/dji2quectel.sh" /tmp/dji2quectel.sh

log "传输平台镜像到 VM（docker save | load）..."
docker save "$PLATFORM_IMAGE" | orb -m "$VM_NAME" docker load

# ── 6. VM 内执行初始化 ──────────────────────────────────
log "在 VM 内执行初始化..."
orb -m "$VM_NAME" sudo bash /tmp/vm-init.sh

# ── 7. 输出访问信息 ─────────────────────────────────────
VM_IP=$(orb -m "$VM_NAME" ip 2>/dev/null | head -1 || orb -m "$VM_NAME" hostname -I | awk '{print $1}')
printf "\n"
ok "全部完成！"
printf "\n  后台地址: http://%s:7575\n" "$VM_IP"
printf "  查看密码: orb -m %s docker logs vohive 2>&1 | grep 密码\n" "$VM_NAME"
printf "  （未传 PROXY_WEB_PASSWORD 时每次启动生成随机密码）\n\n"
```

- [ ] **Step 4: 语法检查所有脚本**

```bash
cd /Users/dannyge/dev/github/vohive
bash -n scripts/lib/common.sh
bash -n scripts/vm-init.sh
bash -n scripts/setup.sh
```

Expected: 三个都无输出（语法正确）。

- [ ] **Step 5: 设置可执行权限**

```bash
cd /Users/dannyge/dev/github/vohive
chmod +x scripts/setup.sh scripts/vm-init.sh scripts/fetch-assets.sh scripts/lib/common.sh
```

- [ ] **Step 6: 提交**

```bash
cd /Users/dannyge/dev/github/vohive
git add scripts/
git commit -m "feat: add macOS OrbStack deployment scripts

- setup.sh: Mac-side orchestrator (check OrbStack → create VM → USB passthrough → push → init)
- vm-init.sh: in-VM init (install docker → rewrite USB → run platform)
- lib/common.sh: shared helpers (logging, checks)
- idempotent: re-runnable, skips existing VM/containers/identity"
```

---

## Task 9: docker-compose 示例 + 项目 README

**Files:**
- Create: `docker-compose.yml`
- Create: `README.md`

**spec 依据**：第 3.3 节场景 2（原生 Linux）；整体说明。

- [ ] **Step 1: 编写 docker-compose.yml（原生 Linux 场景示例）**

Create `docker-compose.yml`:

```yaml
# 原生 Linux 场景示例：改身份（一次性）+ 起平台
# 用法: docker compose up
# 注意: 改身份只需首次运行一次，之后可注释掉 dji2quectel 服务
services:
  # 大疆→移远改身份（一次性，幂等；已是 Quectel 身份会自动跳过）
  dji2quectel:
    image: dji2quectel:latest
    container_name: dji2quectel
    privileged: true
    volumes:
      - /sys:/sys
      - /lib/modules:/lib/modules:ro
      - /dev:/dev
    restart: "no"

  # openvohive 平台（常驻）
  openvohive:
    image: openvohive:latest
    container_name: vohive
    depends_on:
      dji2quectel:
        condition: service_completed_successfully
    privileged: true
    volumes:
      - /dev:/dev
      - vohive-data:/app/data
    ports:
      - "7575:7575"
    environment:
      - PROXY_WEB_USERNAME=admin
      # 不传 PROXY_WEB_PASSWORD 则每次启动生成随机密码（见 docker logs）
      # - PROXY_WEB_PASSWORD=your-strong-password
      # Telegram 转发（可选）
      # - PROXY_TELEGRAM_ENABLED=true
      # - PROXY_TELEGRAM_BOT_TOKEN=123:abc
      # - PROXY_TELEGRAM_ADMIN_ID=your-id
    restart: unless-stopped

volumes:
  vohive-data:
```

- [ ] **Step 2: 验证 compose 配置语法**

```bash
cd /Users/dannyge/dev/github/vohive
docker compose config
```

Expected: 输出解析后的完整 compose 配置，无报错。

- [ ] **Step 3: 编写项目 README.md**

Create `README.md`:

````markdown
# VoHive Docker 镜像

面向高通 4G/5G 模组（Quectel EC20/EC25/EG25 等）的 VoHive 部署方案，提供 Docker 镜像和一键部署脚本。

## 交付物

| 镜像/脚本 | 说明 |
|---|---|
| **openvohive** | 开源版，聚焦短信收发/转发（Telegram/Email/Webhook），主力 |
| **vohive-legacy** | 闭源完整版 v1.5.5（含 VoWiFi/代理等），过渡兼容 |
| **dji2quectel** | 把大疆 4G 模块改写为移远 Quectel 身份（一次性工具） |
| **setup.sh** | macOS 上用 OrbStack 一键部署 |

## 快速开始

### macOS 用户

```bash
git clone --recurse-submodules <本仓库>
cd vohive
bash scripts/fetch-assets.sh        # 下载 legacy 二进制（构建 legacy 时需要）
./scripts/setup.sh                  # 一键部署
```

### 原生 Linux 用户

```bash
git clone --recurse-submodules <本仓库>
cd vohive
bash scripts/fetch-assets.sh
docker buildx bake --load           # 构建三镜像
docker compose up                   # 改身份 + 起平台
```

访问 `http://<IP>:7575`，默认账号 `admin`。未设密码时 `docker logs vohive | grep 密码` 查看随机密码。

## 配置

全部通过环境变量注入（`PROXY_*` 前缀），无需挂载配置文件：

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROXY_WEB_USERNAME` | `admin` | Web 用户名 |
| `PROXY_WEB_PASSWORD` | 随机生成 | Web 密码（不设则每次启动随机，见日志） |
| `PROXY_SERVER_PORT` | `7575` | 服务端口 |
| `PROXY_TELEGRAM_*` | 禁用 | Telegram 转发配置 |
| `PROXY_WEBHOOK_*` | 禁用 | Webhook 配置 |
| `PROXY_EMAIL_*` | 禁用 | Email 配置 |

## 构建

```bash
# 多架构（amd64 + arm64）
docker buildx bake --load

# 推送到 registry
REGISTRY=your-registry.com docker buildx bake --push
```

## 数据持久化

挂载 `/app/data` 目录（含 SQLite 库和日志）：
```bash
-v vohive-data:/app/data
```

## 子模块

本仓库使用 git submodule 管理外部依赖。clone 后需：
```bash
git submodule update --init --recursive
```

| submodule | 来源 | 用途 |
|---|---|---|
| `ref/vohive-release` | iniwex5/vohive-release | 参考（install.sh 模板） |
| `ref/dji-4g-vohive-mac` | wlzh/dji-4g-vohive-mac | 参考（mcc-mnc-table.json、改身份教程） |
| `openvohive/src` | openvohive/openvohive | openvohive 镜像的源码 |

## License 与免责

- openvohive 镜像基于 [openvohive/openvohive](https://github.com/openvohive/openvohive)（PolyForm Noncommercial，仅非商业）
- vohive-legacy 含闭源二进制（原作者 iniwex5，已停维），仅供过渡兼容
- 本软件仅供个人内部测试，严禁商业及非法用途，使用者自行承担法律责任

详见 `docs/superpowers/specs/2026-07-08-vohive-docker-images-design.md`。
````

- [ ] **Step 4: 提交**

```bash
cd /Users/dannyge/dev/github/vohive
git add docker-compose.yml README.md
git commit -m "docs: add docker-compose example and project README"
```

---

## 完成后验证

- [ ] **Step 1: 完整构建三镜像（amd64）**

```bash
cd /Users/dannyge/dev/github/vohive
docker buildx bake --load --set *.platform=linux/amd64
```

Expected: 3 个镜像构建成功。

- [ ] **Step 2: 镜像清单检查**

```bash
docker images | grep -E "openvohive|vohive-legacy|dji2quectel"
```

Expected: 3 个镜像都在。

- [ ] **Step 3: 对照 spec 验收标准逐项核对**

对照 `docs/superpowers/specs/2026-07-08-vohive-docker-images-design.md` 第 11 节验收标准：
- [ ] `docker buildx bake` 成功构建三个镜像的 manifest（本机 amd64 已验证；arm64 需启用 QEMU 或在 arm 机器上验证）
- [ ] openvohive：传入 PROXY_WEB_PASSWORD 能登录；不传时日志打印随机密码
- [ ] vohive-legacy：entrypoint 正确渲染 config.yaml，二进制能加载
- [ ] dji2quectel.sh：无设备时优雅报错（真实模块测试需硬件）
- [ ] dji2quectel.sh：幂等逻辑（已是 Quectel 身份跳过——需硬件验证）

- [ ] **Step 4: git 历史检查**

```bash
git log --oneline
```

Expected: 看到 Task 1-9 的 commit，逻辑清晰。
