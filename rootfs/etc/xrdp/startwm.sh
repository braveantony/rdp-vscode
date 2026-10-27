#!/bin/bash
# Run by xrdp-sesman as the logged-in account for every RDP connection. sesman
# uses Policy=Separate, so each connection has its own display; this script
# gives it its own VSCodium data dir, runtime dir and D-Bus so two sessions of
# the same account never share an instance. Settings are shared through a
# symlink to ~/.config/VSCodium/User. Closing VSCodium ends the session.
set -u
export LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 TZ=Asia/Taipei NO_AT_BRIDGE=1

# Container env does not reach sesman sessions; entrypoint.sh saves it here
# shellcheck source=/dev/null
[ -r /run/rdp-vscode/session.env ] && . /run/rdp-vscode/session.env
VSCODIUM_LOCALE=${VSCODIUM_LOCALE:-zh-tw}
SSH_HOST_ALIAS=${SSH_HOST_ALIAS-tkadm}
SSH_REMOTE_FOLDER=${SSH_REMOTE_FOLDER:-/home/bigred}

# sesman sets DISPLAY=:N.0; the socket is /tmp/.X11-unix/XN
dnum=${DISPLAY#*:}
dnum=${dnum%%.*}
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# Keyed by display and UID: a stale directory left by another account on the
# same display number (sticky /tmp/sess) can never block this session
S="/tmp/sess/$dnum.$(id -u)"
rm -rf "$S"
umask 077
mkdir -m 700 "$S" "$S/data" "$S/run"
mkdir -p "$HOME/.config/VSCodium/User"
ln -s "$HOME/.config/VSCodium/User" "$S/data/User"
export XDG_RUNTIME_DIR="$S/run"
cd "$HOME" || exit 1

eval "$(dbus-launch --sh-syntax)"

codium_pid=""
cleanup() {
  if [ -n "$codium_pid" ]; then
    kill -TERM "$codium_pid" 2>/dev/null
    for _ in $(seq 20); do kill -0 "$codium_pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL "$codium_pid" 2>/dev/null
  fi
  kill "$DBUS_SESSION_BUS_PID" 2>/dev/null
  pkill -TERM -P $$ 2>/dev/null
  rm -rf "$S"
}
trap cleanup EXIT
trap 'exit 143' TERM HUP INT

/opt/rdp-vscode/sync-extensions.sh "$HOME/.vscode-oss/extensions" ||
  echo "[startwm] extension sync failed" >&2
# Without this, --locale only takes effect from a data dir's second start
ELECTRON_RUN_AS_NODE=1 /usr/share/codium/codium /opt/rdp-vscode/languagepacks.js \
  "$HOME/.vscode-oss/extensions" > "$S/data/languagepacks.json" ||
  echo "[startwm] languagepacks.json failed" >&2

openbox &

args=(--user-data-dir="$S/data" --extensions-dir="$HOME/.vscode-oss/extensions"
      --locale="$VSCODIUM_LOCALE")
if [ -n "$SSH_HOST_ALIAS" ]; then
  args+=(--remote="ssh-remote+$SSH_HOST_ALIAS" "$SSH_REMOTE_FOLDER")
fi
# Run the Electron binary itself: /usr/bin/codium is a launcher that returns
# at once. In the background so a SIGTERM from sesman runs the trap right away.
/usr/share/codium/codium "${args[@]}" &
codium_pid=$!
wait "$codium_pid"
