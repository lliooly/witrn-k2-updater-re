#!/usr/bin/env bash
set -euo pipefail

K2_MODE="${1:-run}"
K2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K2_ARCH="${K2_APP_ARCH:-universal2}"
K2_PYTHON="$K2_ROOT/.venv-app/bin/python"
K2_APP="$K2_ROOT/dist/K2 Updater.app"
cd "$K2_ROOT"

if [[ "$K2_MODE" != "--build-only" ]] && pgrep -x K2Updater >/dev/null; then
    # Ordinary quit invokes the app's busy guard. Do not kill an upgrade.
    /usr/bin/osascript -e 'tell application id "dev.witrn.k2updater" to quit' || true
    if pgrep -x K2Updater >/dev/null; then
        echo "K2 Updater 未退出；请先等待当前任务完成并关闭应用。" >&2
        exit 1
    fi
fi

if [[ ! -x "$K2_PYTHON" ]]; then
    echo "请先创建 .venv-app 并安装 requirements-app.txt，见 docs/macos-app.md。" >&2
    exit 1
fi
mkdir -p "$K2_ROOT/build/ModuleCache" "$K2_ROOT/build/pyinstaller-cache"
export CLANG_MODULE_CACHE_PATH="$K2_ROOT/build/ModuleCache"
export SWIFT_MODULE_CACHE_PATH="$K2_ROOT/build/ModuleCache"
export PYINSTALLER_CONFIG_DIR="$K2_ROOT/build/pyinstaller-cache"
"$K2_PYTHON" script/prepare_backend.py --arch "$K2_ARCH"

K2_SWIFT_ARGS=(--package-path macos --disable-sandbox --cache-path "$K2_ROOT/build/swift-cache" --scratch-path "$K2_ROOT/build/swift" --manifest-cache local -c release)
if [[ "$K2_ARCH" == "universal2" ]]; then
    K2_SWIFT_ARGS+=(--arch arm64 --arch x86_64)
else
    K2_SWIFT_ARGS+=(--arch "$K2_ARCH")
fi
swift build "${K2_SWIFT_ARGS[@]}"
K2_BIN_DIR="$(swift build "${K2_SWIFT_ARGS[@]}" --show-bin-path)"
swift script/generate_icon.swift "$K2_ROOT/build/K2Updater.iconset"
/usr/bin/iconutil -c icns "$K2_ROOT/build/K2Updater.iconset" -o "$K2_ROOT/build/K2Updater.icns"
"$K2_PYTHON" script/package_app.py --binary "$K2_BIN_DIR/K2Updater" --arch "$K2_ARCH"

case "$K2_MODE" in
    --build-only) ;;
    run) /usr/bin/open -n "$K2_APP" ;;
    --verify) /usr/bin/open -n "$K2_APP"; sleep 1; pgrep -x K2Updater >/dev/null ;;
    --logs|--telemetry)
        /usr/bin/open -n "$K2_APP"
        /usr/bin/log stream --info --style compact --predicate 'process == "K2Updater"'
        ;;
    --debug) lldb -- "$K2_APP/Contents/MacOS/K2Updater" ;;
    *) echo "usage: $0 [run|--build-only|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
