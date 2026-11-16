#!/bin/bash
# Run by xrdp-sesman as the logged-in account for every RDP connection. sesman
# uses Policy=Separate, so each connection has its own display; this script
# gives it its own VSCodium data dir, runtime dir and D-Bus so two sessions of
# the same account never share an instance. Settings are shared through a
# symlink to ~/.config/VSCodium/User. Closing VSCodium ends the session.
# In attached mode (RDP_ATTACHED=1, set by attached-session.sh) the launcher
# runs this script instead of sesman: the desktop, its window manager and its
# input method belong to another container, so only VSCodium is started here.
set -u
RDP_ATTACHED=${RDP_ATTACHED:-0}
export LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 TZ=Asia/Taipei NO_AT_BRIDGE=1

# Container env does not reach sesman sessions; entrypoint.sh saves it here
# shellcheck source=/dev/null
[ -r /run/rdp-vscode/session.env ] && . /run/rdp-vscode/session.env
VSCODIUM_LOCALE=${VSCODIUM_LOCALE:-zh-tw}
SSH_AUTO_CONNECT=${SSH_AUTO_CONNECT:-false}
SSH_HOST_ALIAS=${SSH_HOST_ALIAS:-tkadm}
SSH_REMOTE_FOLDER=${SSH_REMOTE_FOLDER:-/home/bigred}

# sesman sets DISPLAY=:N.0; the socket is /tmp/.X11-unix/XN
dnum=${DISPLAY#*:}
dnum=${dnum%%.*}
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

# Keyed by display and UID, so another account's leftover on the same display
# number does not collide. A directory that this account cannot remove (another
# account created it in the sticky /tmp/sess) is refused, never reused.
S="/tmp/sess/$dnum.$(id -u)"
if [ "$RDP_ATTACHED" = 1 ] && [ -O "$S/data" ] &&
   pgrep -u "$(id -u)" -f -- "^/usr/share/codium/codium --user-data-dir=$S/data " >/dev/null; then
  # Asked again while VSCodium is open on this desktop: hand over to the
  # running instance (it opens a window) instead of wiping its data dir
  exec /usr/share/codium/codium --user-data-dir="$S/data" \
    --extensions-dir="$HOME/.vscode-oss/extensions" --new-window
fi
rm -rf "$S" 2>/dev/null
umask 077
if ! mkdir -m 700 "$S"; then
  echo "[startwm] $S exists and is not ours; refusing to start" >&2
  exit 1
fi
mkdir -m 700 "$S/data" "$S/run"
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

if [ "$RDP_ATTACHED" = 1 ]; then
  # The desktop's input method is reached over X (XIM); GTK's own XIM module
  # is in every image, the desktop's input method module is not
  export GTK_IM_MODULE=xim XMODIFIERS=@im=fcitx
else
  openbox &
fi

args=(--user-data-dir="$S/data" --extensions-dir="$HOME/.vscode-oss/extensions"
      --locale="$VSCODIUM_LOCALE")
if [ "$SSH_AUTO_CONNECT" = true ]; then
  args+=(--remote="ssh-remote+$SSH_HOST_ALIAS" "$SSH_REMOTE_FOLDER")
fi
# Run the Electron binary itself: /usr/bin/codium is a launcher that returns
# at once. In the background so a SIGTERM from sesman runs the trap right away.
/usr/share/codium/codium "${args[@]}" &
codium_pid=$!
wait "$codium_pid"
