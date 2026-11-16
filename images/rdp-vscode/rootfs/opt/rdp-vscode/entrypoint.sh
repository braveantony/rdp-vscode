#!/usr/bin/env bash
# Started by tini as root: xrdp-sesman needs root for PAM and to switch to the
# login user.
# RDP_MODE=standalone (default): this container is the desktop; users connect
#   to its xrdp.
# RDP_MODE=attached: no xrdp here. Another container of the pod is the desktop
#   and creates the homes; this one starts VSCodium on that desktop when asked
#   (see launcher.pl).
set -eu
RDP_MODE=${RDP_MODE:-standalone}
case $RDP_MODE in
  standalone | attached) ;;
  *) echo "[entrypoint] invalid RDP_MODE: $RDP_MODE (want standalone or attached)" >&2; exit 1 ;;
esac
MAX_SESSIONS=${MAX_SESSIONS:-3}
case $MAX_SESSIONS in
  '' | *[!0-9]*) echo "[entrypoint] invalid MAX_SESSIONS: $MAX_SESSIONS" >&2; exit 1 ;;
esac

homes=homes
[ "$RDP_MODE" = standalone ] || homes=no-homes
users=$(/opt/rdp-vscode/accounts.sh "${USERS_FILE:-/etc/rdp-vscode/users}" "$homes")
unset RDP_PASSWORD
echo "[entrypoint] accounts: $users"

/opt/rdp-vscode/ssh-config.sh > /etc/ssh/ssh_config.d/rdp-vscode.conf
/opt/rdp-vscode/font-config.sh > /etc/fonts/local.conf

# sesman starts sessions with a clean environment; startwm.sh reads this file
install -d -m 755 /run/rdp-vscode
/opt/rdp-vscode/session-env.sh > /run/rdp-vscode/session.env
chmod 644 /run/rdp-vscode/session.env

rm -rf /tmp/sess
# Per-session data lives under /tmp/sess (see startwm.sh); every account may
# create its own entries, the sticky bit keeps them from touching others'
install -d -m 1777 /tmp/sess

if [ "$RDP_MODE" = attached ]; then
  LAUNCH_SOCKET=${LAUNCH_SOCKET:-/run/rdp-workspace/vscode.sock}
  HOME_WAIT=${HOME_WAIT:-300}
  case $HOME_WAIT in
    '' | *[!0-9]*) echo "[entrypoint] invalid HOME_WAIT: $HOME_WAIT" >&2; exit 1 ;;
  esac
  rm -f "$LAUNCH_SOCKET"
  # The desktop container creates the homes. Serve only once they exist, then
  # add this image's default files (VSCodium settings) without replacing any.
  for user in $users; do
    waited=0
    until [ -d "/home/$user" ] && [ "$(stat -c %u "/home/$user")" = "$(id -u "$user")" ]; do
      if [ "$waited" -ge "$HOME_WAIT" ]; then
        echo "[entrypoint] /home/$user did not appear within ${HOME_WAIT}s (the desktop container creates it)" >&2
        exit 1
      fi
      [ "$waited" -ne 0 ] || echo "[entrypoint] waiting for /home/$user"
      sleep 1
      waited=$((waited + 1))
    done
    runuser -u "$user" -- cp -R --no-clobber --no-preserve=ownership /etc/skel/. "/home/$user/"
  done
  install -d -m 755 "$(dirname "$LAUNCH_SOCKET")"
  # exec: the launcher is this container's only service; if it exits, K8s restarts the container
  exec /opt/rdp-vscode/launcher.pl "$LAUNCH_SOCKET" /opt/rdp-vscode/attached-session.sh
fi

# Per-pod TLS certificate and RDP RSA keys (the Dockerfile removes the ones
# generated at build time); group xrdp may read them (the listener itself runs
# as root: Debian's xrdp 0.10.1 has no runtime_user)
cd /etc/xrdp
if [ ! -s key.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$(hostname)" \
    -keyout key.pem -out cert.pem 2>/dev/null
fi
[ -s rsakeys.ini ] || xrdp-keygen xrdp rsakeys.ini >/dev/null
chown root:xrdp key.pem cert.pem rsakeys.ini
chmod 640 key.pem cert.pem rsakeys.ini
cd /

rm -rf /run/xrdp/*.pid /var/run/xrdp/*.pid /tmp/.X*-lock /tmp/.X11-unix/X*
sed -i "s/^MaxSessions=.*/MaxSessions=${MAX_SESSIONS}/" /etc/xrdp/sesman.ini

xrdp-sesman --nodaemon &
xrdp --nodaemon &

# Any daemon exiting stops the container so K8s restarts it
wait -n
echo "[entrypoint] a service exited, stopping container" >&2
exit 1
