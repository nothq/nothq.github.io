#!/bin/sh
# Installs a nothq app from its latest GitHub release. notslack by default:
#
#   curl -fsSL https://nothq.github.io/install.sh | sh
#   curl -fsSL https://nothq.github.io/install.sh | sh -s notnotion
#
# macOS: copies <app>.app into /Applications (or ~/Applications) and opens it.
# Linux: unpacks into ~/.local/share/nothq/<app>, links ~/.local/bin/<app>
# and adds a launcher to your applications menu.
set -eu

app=${1:-notslack}
case "$app" in
    notslack)
        summary="Slack, without the browser"
        categories="Network;InstantMessaging;Chat;"
        ;;
    notnotion)
        summary="Notion, without the browser"
        categories="Office;"
        ;;
    *)
        printf 'install.sh: unknown app %s; choose notslack or notnotion\n' "$app" >&2
        exit 1
        ;;
esac
releases=https://github.com/nothq/$app/releases/latest/download

main() {
    tmp=$(mktemp -d)
    trap 'cleanup' EXIT INT TERM
    case "$(uname -s)" in
        Darwin) install_macos ;;
        Linux) install_linux ;;
        *) fail "this installer supports macOS and Linux. On Windows, download $releases/$app-windows-x86_64.zip" ;;
    esac
}

install_macos() {
    case "$(uname -m)" in
        arm64) platform=macos-arm64 ;;
        x86_64)
            # A shell running under Rosetta still gets the native build.
            if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
                platform=macos-arm64
            else
                platform=macos-x86_64
            fi
            ;;
        *) fail "unsupported Mac architecture $(uname -m)" ;;
    esac

    download "$releases/$app-$platform.dmg" "$tmp/$app.dmg"
    mkdir "$tmp/volume"
    hdiutil attach -quiet -nobrowse -noautoopen -readonly -mountpoint "$tmp/volume" "$tmp/$app.dmg"
    mounted=$tmp/volume

    if [ -w /Applications ]; then
        dest=/Applications
    else
        dest=$HOME/Applications
        mkdir -p "$dest"
    fi
    if pgrep -xq "$app"; then
        say "Quitting the running $app"
        osascript -e "quit app \"$app\"" >/dev/null 2>&1 || pkill -x "$app" || true
        sleep 1
    fi
    rm -rf "$dest/$app.app"
    ditto "$mounted/$app.app" "$dest/$app.app"
    hdiutil detach -quiet "$mounted"
    mounted=
    # curl never marks files as downloaded from the internet, but a copy made
    # some other way might be; make sure macOS opens it without asking.
    xattr -dr com.apple.quarantine "$dest/$app.app" 2>/dev/null || true

    say "Installed $app in $dest"
    if [ -z "${NOTHQ_NO_OPEN:-}" ]; then
        open "$dest/$app.app"
    fi
}

install_linux() {
    case "$(uname -m)" in
        x86_64 | amd64) platform=linux-x86_64 ;;
        *) fail "unsupported Linux architecture $(uname -m); $app builds for x86_64" ;;
    esac

    data=${XDG_DATA_HOME:-$HOME/.local/share}
    dest=$data/nothq/$app
    bin=$HOME/.local/bin

    download "$releases/$app-$platform.tar.gz" "$tmp/$app.tar.gz"
    mkdir -p "$tmp/unpack"
    tar -xzf "$tmp/$app.tar.gz" -C "$tmp/unpack" --strip-components=1
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")" "$bin" "$data/applications"
    mv "$tmp/unpack" "$dest"
    ln -sf "$dest/$app" "$bin/$app"

    cat >"$data/applications/$app.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$app
Comment=$summary
Exec=$dest/$app
Terminal=false
Categories=$categories
StartupWMClass=$app
DESKTOP

    say "Installed $app in $dest"
    case ":$PATH:" in
        *":$bin:"*) say "Run it with: $app" ;;
        *) say "Run it with: $bin/$app (or add $bin to your PATH)" ;;
    esac
}

download() {
    say "Downloading $(basename "$1")"
    curl -fL --progress-bar -o "$2" "$1" || fail "could not download $1"
}

cleanup() {
    if [ -n "${mounted:-}" ]; then
        hdiutil detach -quiet "$mounted" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}

say() {
    printf '%s\n' "$*"
}

fail() {
    printf 'install.sh: %s\n' "$*" >&2
    exit 1
}

main "$@"
