#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION=Release
OPEN_APP=false

usage() {
    cat <<'EOF'
用法：./build.sh [--debug] [--open]

默认编译 Release 版 Bitvault，无需配置 Apple 开发者签名。

  --debug   编译 Debug 版
  --open    编译成功后打开 App
  -h, --help  显示帮助

输出：build/Build/Products/Release/Bitvault.app
Debug 版输出到对应的 Debug 目录。
可通过 DEVELOPER_DIR 指定使用的 Xcode。
EOF
}

for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION=Debug ;;
        --open) OPEN_APP=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf '未知参数：%s\n' "$argument" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "$(uname -s)" != Darwin ]]; then
    printf '请在安装了 Xcode 的 Mac 上运行此脚本。\n' >&2
    exit 1
fi

is_xcode() {
    [[ -x "$1/usr/bin/xcodebuild" && -d "$1/Platforms/MacOSX.platform" ]]
}

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    # xcodebuild also accepts the .app path; normalize it for validation.
    if [[ -d "$DEVELOPER_DIR/Contents/Developer" ]]; then
        export DEVELOPER_DIR="$DEVELOPER_DIR/Contents/Developer"
    fi
    if ! is_xcode "$DEVELOPER_DIR"; then
        printf 'DEVELOPER_DIR 不是有效的 Xcode 开发目录：%s\n' "$DEVELOPER_DIR" >&2
        exit 1
    fi
else
    SELECTED_DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    if is_xcode "$SELECTED_DEVELOPER_DIR"; then
        export DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR"
    else
        for XCODE_APP in /Applications/Xcode.app /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
            if is_xcode "$XCODE_APP/Contents/Developer"; then
                export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                break
            fi
        done
    fi
    if [[ -z "${DEVELOPER_DIR:-}" ]]; then
        printf '未找到 Xcode。请先安装 Xcode，或通过 DEVELOPER_DIR 指定路径。\n' >&2
        exit 1
    fi
fi

cd "$SCRIPT_DIR"
if [[ ! -f Prizm/LocalConfig.xcconfig ]]; then
    cp Prizm/LocalConfig.xcconfig.template Prizm/LocalConfig.xcconfig
fi

BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/Bitvault.app"
mkdir -p "$BUILD_DIR"
BUILD_LOG="$BUILD_DIR/build-$CONFIGURATION.log"

printf 'Xcode：%s\n正在编译 Bitvault（%s）…\n' "$DEVELOPER_DIR" "$CONFIGURATION"
if "$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -quiet \
    -project Prizm/Prizm.xcodeproj \
    -scheme Prizm \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    build 2>&1 | tee "$BUILD_LOG"; then
    if [[ ! -d "$APP_PATH" ]]; then
        printf '构建结束，但未找到 App：%s\n' "$APP_PATH" >&2
        exit 1
    fi
else
    printf '\n编译失败，日志：%s\n' "$BUILD_LOG" >&2
    exit 1
fi

printf '\n编译完成：%s\n日志：%s\n' "$APP_PATH" "$BUILD_LOG"
if [[ "$OPEN_APP" == true ]]; then
    /usr/bin/open "$APP_PATH"
fi
