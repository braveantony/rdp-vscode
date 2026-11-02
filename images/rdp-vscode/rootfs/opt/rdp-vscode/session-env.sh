#!/usr/bin/env bash
# Print the session settings that startwm.sh sources: sesman starts sessions
# with a clean environment, so the container env has to be saved to a file.
set -eu

auto=${SSH_AUTO_CONNECT:-false}
case $auto in
  true | false) ;;
  *) echo "[entrypoint] invalid SSH_AUTO_CONNECT: $auto (want true or false); using false" >&2
     auto=false ;;
esac

printf 'VSCODIUM_LOCALE=%q\n' "${VSCODIUM_LOCALE:-zh-tw}"
printf 'SSH_AUTO_CONNECT=%q\n' "$auto"
printf 'SSH_HOST_ALIAS=%q\n' "${SSH_HOST_ALIAS:-tkadm}"
printf 'SSH_REMOTE_FOLDER=%q\n' "${SSH_REMOTE_FOLDER:-/home/${SSH_USER:-bigred}}"
