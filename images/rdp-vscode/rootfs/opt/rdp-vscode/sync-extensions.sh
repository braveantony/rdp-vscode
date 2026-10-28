#!/usr/bin/env bash
# Install the image's pinned extensions into a user's extensions dir:
#   sync-extensions.sh <user-extensions-dir>
# For each /opt/rdp-vscode/vsix/<publisher>.<name>-<version>.vsix, drop other
# versions of that extension and install this one with --install-extension
# (copying the directory is ignored once extensions.json exists). Extensions
# the user installed are left alone; a second run changes nothing.
set -eu
dir=$1
vsix_dir=${RDP_VSCODE_VSIX_DIR:-/opt/rdp-vscode/vsix}
mkdir -p "$dir"

ud=$(mktemp -d)
trap 'rm -rf "$ud"' EXIT
for vsix in "$vsix_dir"/*.vsix; do
  [ -e "$vsix" ] || continue
  want=$(basename "$vsix" .vsix)
  [ -d "$dir/$want" ] && continue
  id=${want%-*}
  for old in "$dir/$id"-[0-9]*; do
    [ -d "$old" ] && rm -rf "$old"
  done
  codium --user-data-dir "$ud" --extensions-dir "$dir" --install-extension "$vsix" --force >/dev/null
done
