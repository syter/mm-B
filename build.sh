#!/usr/bin/env bash
# 打包发布版。默认同时出 Windows 单文件 exe 和网页版，各自压成 zip。
#
#   ./build.sh              两个都打
#   ./build.sh win          只打 Windows
#   ./build.sh web          只打网页版
#   ./build.sh --skip-tests 跳过测试（不建议，默认会先跑一遍回归测试）
#
# 产物在 build/ 底下，文件名带版本号，版本号读 project.godot 的 config/version。

set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
TARGET="both"
RUN_TESTS=1

for arg in "$@"; do
  case "$arg" in
    win|windows) TARGET="win" ;;
    web) TARGET="web" ;;
    --skip-tests) RUN_TESTS=0 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "不认识的参数：$arg（用 -h 看用法）" >&2; exit 2 ;;
  esac
done

command -v "$GODOT" >/dev/null 2>&1 || {
  echo "✗ 找不到 godot。装了但不在 PATH 里的话，用 GODOT=/path/to/godot ./build.sh" >&2
  exit 1
}

NAME="$(sed -n 's/^config\/name="\(.*\)"$/\1/p' project.godot | head -1)"
VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot | head -1)"
: "${NAME:=game}"
: "${VERSION:=dev}"

# 导出模板不在的话 Godot 只会丢一句看不懂的错，这里提前拦住并说清楚怎么装
GODOT_VER="$("$GODOT" --version 2>/dev/null | head -1 | sed 's/\.official.*//')"
TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VER"
[ -d "$TPL_DIR" ] || TPL_DIR="$HOME/.local/share/godot/export_templates/$GODOT_VER"
if [ ! -d "$TPL_DIR" ]; then
  cat >&2 <<EOF
✗ 没装导出模板（Godot 默认不带，1.28GB）。

  从 https://github.com/godotengine/godot/releases/tag/${GODOT_VER%%.stable*}-stable
  下载 Godot_v*_export_templates.tpz，解压后把 templates/ 里的文件放到：
    $TPL_DIR/
EOF
  exit 1
fi

# Godot 的日志行首带 ANSI 颜色码，得先剥掉转义序列再过滤，否则漏网
strip_noise() {
  sed $'s/\033\[[0-9;]*m//g' \
    | grep -viE '^\[|DONE|Godot Engine|savepack|storing|^$' || true
}

echo "==> $NAME v$VERSION  (Godot $GODOT_VER)"

if [ "$RUN_TESTS" -eq 1 ]; then
  echo "==> 跑回归测试"
  for t in tests/regression/test_core.gd tests/regression/test_ui_smoke.gd; do
    out="$("$GODOT" --headless --path . --script "res://$t" 2>&1 | grep -E '通过, .*失败' || true)"
    echo "    $(basename "$t"): ${out:-没有输出}"
    case "$out" in
      *"0 失败"*) ;;
      *) echo "✗ $t 没过，不打包。要强行打包加 --skip-tests" >&2; exit 1 ;;
    esac
  done
fi

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p build

pack_win() {
  echo "==> 导出 Windows"
  rm -rf build/windows && mkdir -p build/windows
  "$GODOT" --headless --path . --export-release "Windows Desktop" \
    "build/windows/$NAME.exe" 2>&1 | strip_noise
  [ -f "build/windows/$NAME.exe" ] || { echo "✗ 导出失败，没生成 exe" >&2; exit 1; }
  local zip="build/$NAME-v$VERSION-windows.zip"
  rm -f "$zip"
  ( cd build/windows && zip -q -9 "../$(basename "$zip")" "$NAME.exe" )
  echo "    $zip  ($(du -h "$zip" | cut -f1))"
}

pack_web() {
  echo "==> 导出 Web"
  rm -rf build/web && mkdir -p build/web
  "$GODOT" --headless --path . --export-release "Web" \
    "build/web/index.html" 2>&1 | strip_noise
  [ -f "build/web/index.wasm" ] || { echo "✗ 导出失败，没生成 wasm" >&2; exit 1; }
  local zip="build/$NAME-v$VERSION-web.zip"
  rm -f "$zip"
  ( cd build/web && zip -q -9 -r "../$(basename "$zip")" . )
  echo "    $zip  ($(du -h "$zip" | cut -f1))"
}

case "$TARGET" in
  win) pack_win ;;
  web) pack_web ;;
  both) pack_win; pack_web ;;
esac

echo "==> 完成，产物在 $(pwd)/build/"
