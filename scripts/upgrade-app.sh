#!/bin/bash
# DSH Desktop app-content swap (upgrade the installed .app to this checkout).
# Archived copy of ~/dsh-upgrade/swap-app.sh (portable: REPO resolves from this
# script's location). See DECISIONS.md D-014/D-015 in Siq5005/dsh-plugins.
#
# 用法: 先在 GUI 里退出 DSH Desktop, 然后:
#   bash scripts/upgrade-app.sh                 # 默认目标 /Applications/DSH Desktop.app
#   APP_PATH=/path/to/DSH\ Desktop.app bash scripts/upgrade-app.sh
#
# 门槛: 0) 用本 checkout 的新核心 boot 真实 web profile (smoke-web-profile),
# 否则插件 client bundle 链接错误(如 @deepseek-ai/dsh-settings 删导出导致的
# SyntaxError)只会在 GUI 启动时才炸。4) 替换后复检真实 web profile。
#
# 回滚: mv "$APP_PATH/Contents/Resources/app" .../app.broken
#       mv <backup dir>/app-* "$APP_PATH/Contents/Resources/app"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"                    # dsh-desktop checkout (this repo)
APP_PATH="${APP_PATH:-/Applications/DSH Desktop.app}"
APP="$APP_PATH/Contents/Resources/app"
BK="${DSH_UPGRADE_BACKUP:-$HOME/dsh-upgrade/backup-app}"

# 0. 决不允许在 app 运行时替换
if pgrep -f "DSH Desktop.app/Contents/MacOS/DSH Desktop" >/dev/null 2>&1; then
  echo "ERROR: DSH Desktop 仍在运行。请先在 GUI 中退出 (Cmd+Q), 再重跑本脚本。" >&2
  exit 1
fi

# Node 可能在 /opt/homebrew/bin (Homebrew) 或已在 PATH
if ! command -v node >/dev/null 2>&1 && [ -x /opt/homebrew/bin/node ]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi

web_profile_smoke() {
  # $1 = checkout 目录 (其 node_modules 提供核心)
  ( cd "$1" && DSH_DESKTOP_PROFILE=web node --expose-internals scripts/smoke-web-profile.mjs )
}

# 0.5 预检: 本 checkout 的核心 + 真实 web profile 必须能 boot
echo "== 0/5 预检: 本核心 boot 真实 web profile (smoke-web-profile)"
if ! web_profile_smoke "$REPO" 2>&1 | tail -6 | grep -q "OK: web profile booted"; then
  echo "== 0/5 FAILED: web profile 在本核心下 boot 失败, 中止替换。" >&2
  echo "   原因通常是插件仍在使用旧核心删掉的 API; 用 pnpm patch 打兼容层后再重试。" >&2
  exit 1
fi
echo "== 0/5 OK: web profile 可 boot, 继续。"

# 1. 备份当前 app 内容 (只改名不删除)
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"
echo "== 1/5 备份旧 app 内容 -> $BK/app-$STAMP"
mv "$APP" "$BK/app-$STAMP"

# 2. 复制本 checkout 内容; 排除 .git / node_modules 之外的构建杂物
echo "== 2/5 复制本 checkout 内容 -> $APP"
mkdir -p "$APP"
tar -C "$REPO" --exclude='.git' --exclude='release' --exclude='node_modules/electron' -cf - . | tar -C "$APP" -xf -
rm -rf "$APP/.git"

# 3. 自检: 替换后的副本跑隔离桌面冒烟 (不碰 ~/.dsh)
echo "== 3/5 自检 smoke-boot (隔离 DSH_HOME=/tmp/dsh-swap-check)"
rm -rf /tmp/dsh-swap-check
if DSH_HOME=/tmp/dsh-swap-check node --expose-internals "$APP/scripts/smoke-boot.mjs" 2>&1 | tail -5 | grep -q "OK: desktop-shell booted"; then
  echo "== 3/5 OK: 替换后的副本通过 smoke-boot"
else
  echo "== 3/5 FAILED: 自检失败, 正在回滚……" >&2
  rm -rf "$APP"
  mv "$BK/app-$STAMP" "$APP"
  echo "已回滚到旧版。请检查输出后重试。" >&2
  exit 1
fi

# 4. 替换后复检: 用替换后的副本 boot 真实 web profile
echo "== 4/5 复检: 替换后的副本 boot 真实 web profile"
if ! web_profile_smoke "$APP" 2>&1 | tail -6 | grep -q "OK: web profile booted"; then
  echo "== 4/5 FAILED: 替换后的应用无法 boot 真实 web profile, 正在回滚……" >&2
  rm -rf "$APP"
  mv "$BK/app-$STAMP" "$APP"
  echo "已回滚到旧版。请检查输出后重试。" >&2
  exit 1
fi
echo "== 4/5 OK: 替换后的副本可 boot 真实 web profile"

# 5. 完成
echo "== 5/5 完成。备份保留在: $BK (回滚材料)"
ls "$BK"
echo
echo "现在请重新打开 DSH Desktop, 然后在会话列表里点开本对话继续验证。"