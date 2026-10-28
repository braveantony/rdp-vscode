#!/usr/bin/env bash
# Tests for languagepacks.js, run inside the image: bash test/unit/languagepacks.test.sh [image]
# shellcheck disable=SC1091,SC2015,SC2016  # pass() never fails; single-quoted scripts expand inside the container
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
IMG=${1:-localhost/rdp-vscode:dev}
zh=$(sed -n 's/^ARG ZH_HANT_VERSION=//p' images/rdp-vscode/Dockerfile)
run() { podman run --rm --user 65534 -e HOME=/tmp -e ZH="$zh" --entrypoint bash "$IMG" -c "$1"; }
gen='ELECTRON_RUN_AS_NODE=1 /usr/share/codium/codium /opt/rdp-vscode/languagepacks.js'
q() { printf "ELECTRON_RUN_AS_NODE=1 /usr/share/codium/codium -e 'const j=JSON.parse(require(\"fs\").readFileSync(\"/tmp/lp.json\",\"utf8\")); process.stdout.write(String(%s))'" "$1"; }

say zh-tw-pack
run "/opt/rdp-vscode/sync-extensions.sh /tmp/ext >/dev/null 2>&1 && $gen /tmp/ext > /tmp/lp.json || exit 9
     d=/tmp/ext/ms-ceintl.vscode-language-pack-zh-hant-\$ZH
     want=\$(printf %s \"ms-ceintl.vscode-language-pack-zh-hant\$ZH\" | md5sum | cut -d' ' -f1)
     [ \"\$($(q 'j["zh-tw"].hash'))\" = \"\$want\" ] || exit 2
     [ \"\$($(q 'j["zh-tw"].translations.vscode'))\" = \"\$d/translations/main.i18n.json\" ] || exit 3
     [ \"\$($(q 'j["zh-tw"].label'))\" = '中文(繁體)' ] || exit 4
     [ \"\$($(q 'j["zh-tw"].extensions[0].extensionIdentifier.id'))\" = ms-ceintl.vscode-language-pack-zh-hant ] || exit 5
     [ \"\$($(q 'Object.keys(j).join()'))\" = zh-tw ] || exit 6" \
  && pass "zh-tw entry matches VSCodium's format" || bad "zh-tw entry (rc=$?)"

say no-packs
run "mkdir -p /tmp/empty && $gen /tmp/empty > /tmp/lp.json && [ \"\$($(q 'Object.keys(j).length'))\" = 0 ]" \
  && pass "empty extensions dir gives {}" || bad "empty extensions dir (rc=$?)"

finish
