#!/usr/bin/env bash
# Sys Manager installer
#   ./install.sh            build + install/upgrade all Plasma widgets and the `sys-manager` command
#   ./install.sh build      only build packages into ./build
#   ./install.sh uninstall  remove widgets and the command
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
WIDGETS=(cpu ram gpu disk net overview)
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sys-manager"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

build() {
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    for w in "${WIDGETS[@]}"; do
        local out="$BUILD/org.sysmanager.$w"
        cp -r "$ROOT/plasma/widgets/$w" "$out"
        mkdir -p "$out/contents/ui" "$out/contents/config" "$out/contents/code"
        cp "$ROOT"/plasma/common/*.qml "$ROOT"/plasma/common/*.js "$out/contents/ui/"
        cp "$ROOT/plasma/common/config/main.xml" "$out/contents/config/"
        cp "$ROOT/backend/sysmanager.py" "$out/contents/code/"
        chmod +x "$out/contents/code/sysmanager.py"
    done
    echo "Built ${#WIDGETS[@]} widget packages in $BUILD"
}

install_widgets() {
    command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 not found (Plasma 6 required)"; exit 1; }
    for w in "${WIDGETS[@]}"; do
        local pkg="$BUILD/org.sysmanager.$w"
        if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "org.sysmanager.$w"; then
            kpackagetool6 -t Plasma/Applet -u "$pkg" >/dev/null && echo "Upgraded   org.sysmanager.$w"
        else
            kpackagetool6 -t Plasma/Applet -i "$pkg" >/dev/null && echo "Installed  org.sysmanager.$w"
        fi
    done
}

install_cli() {
    mkdir -p "$SHARE_DIR" "$BIN_DIR" "$APPS_DIR"
    cp "$ROOT/backend/sysmanager.py" "$SHARE_DIR/sysmanager.py"
    cat > "$BIN_DIR/sys-manager" <<EOF
#!/usr/bin/env bash
exec python3 "$SHARE_DIR/sysmanager.py" "\$@"
EOF
    chmod +x "$BIN_DIR/sys-manager"
    cat > "$APPS_DIR/sys-manager.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Sys Manager
GenericName=System Monitor
Comment=CPU, memory, GPU, disk and network monitor
Exec=python3 "$SHARE_DIR/sysmanager.py" tui
Icon=utilities-system-monitor
Terminal=true
Categories=System;Monitor;
EOF
    echo "Installed  $BIN_DIR/sys-manager (terminal monitor) + app menu entry"
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "  note: $BIN_DIR is not in your PATH" ;; esac
}

uninstall() {
    for w in "${WIDGETS[@]}"; do
        kpackagetool6 -t Plasma/Applet -r "org.sysmanager.$w" >/dev/null 2>&1 && echo "Removed    org.sysmanager.$w" || true
    done
    rm -f "$BIN_DIR/sys-manager" "$APPS_DIR/sys-manager.desktop"
    rm -rf "$SHARE_DIR" "${XDG_CACHE_HOME:-$HOME/.cache}/sys-manager"
    echo "Done."
}

case "${1:-install}" in
    build) build ;;
    install)
        build
        install_widgets
        install_cli
        echo
        echo "Add widgets: right-click desktop or panel -> Add or Manage Widgets -> search \"Sys Manager\"."
        echo "If a widget was already placed, restart Plasma to load the new version:"
        echo "  systemctl --user restart plasma-plasmashell"
        ;;
    uninstall) uninstall ;;
    *) echo "usage: $0 [install|build|uninstall]"; exit 1 ;;
esac
