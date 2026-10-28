#!/usr/bin/env bash
# Started by tini as root: xrdp-sesman needs root for PAM and to switch to the
# login user.
set -eu
MAX_SESSIONS=${MAX_SESSIONS:-3}
case $MAX_SESSIONS in
  '' | *[!0-9]*) echo "[entrypoint] invalid MAX_SESSIONS: $MAX_SESSIONS" >&2; exit 1 ;;
esac

users=$(/opt/rdp-vscode/accounts.sh "${USERS_FILE:-/etc/rdp-vscode/users}")
unset RDP_PASSWORD
echo "[entrypoint] accounts: $users"

/opt/rdp-vscode/ssh-config.sh > /etc/ssh/ssh_config.d/rdp-vscode.conf
/opt/rdp-vscode/font-config.sh > /etc/fonts/local.conf

# sesman starts sessions with a clean environment; startwm.sh reads this file
install -d -m 755 /run/rdp-vscode
{
  printf 'VSCODIUM_LOCALE=%q\n' "${VSCODIUM_LOCALE:-zh-tw}"
  printf 'SSH_HOST_ALIAS=%q\n' "${SSH_HOST_ALIAS-tkadm}"
  printf 'SSH_REMOTE_FOLDER=%q\n' "${SSH_REMOTE_FOLDER:-/home/${SSH_USER:-bigred}}"
} > /run/rdp-vscode/session.env
chmod 644 /run/rdp-vscode/session.env

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

rm -rf /run/xrdp/*.pid /var/run/xrdp/*.pid /tmp/.X*-lock /tmp/.X11-unix/X* /tmp/sess

# Per-session data lives under /tmp/sess (see startwm.sh); every account may
# create its own entries, the sticky bit keeps them from touching others'
install -d -m 1777 /tmp/sess
sed -i "s/^MaxSessions=.*/MaxSessions=${MAX_SESSIONS}/" /etc/xrdp/sesman.ini

xrdp-sesman --nodaemon &
xrdp --nodaemon &

# Any daemon exiting stops the container so K8s restarts it
wait -n
echo "[entrypoint] a service exited, stopping container" >&2
exit 1
