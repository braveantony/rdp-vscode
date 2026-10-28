#!/usr/bin/env bash
# Unit tests for images/rdp-vscode/rootfs/opt/rdp-vscode/font-config.sh
# shellcheck disable=SC1091,SC2015  # pass() never fails, so A && B || C is safe here
set -u
cd "$(dirname "$0")/../.." || exit 1
. test/lib.sh
GEN=images/rdp-vscode/rootfs/opt/rdp-vscode/font-config.sh
unset VSCODIUM_FONT

# Families strongly prepended to monospace, one per line, in order. A weak
# <prefer> loses to the zh_TW locale, which pulls Noto CJK ahead of it.
families() {
  python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for m in root.iter("match"):
    if m.findtext("test/string") == "monospace":
        e = m.find("edit")
        assert e.get("mode") == "prepend" and e.get("binding") == "strong", e.attrib
        for f in e.iter("string"):
            print(f.text)
'
}

check() { # name, VSCODIUM_FONT value ("-" = unset), expected families
  local name=$1 val=$2 want=$3 out got
  if [ "$val" = - ]; then out=$(bash "$GEN" 2>/dev/null); else out=$(VSCODIUM_FONT=$val bash "$GEN" 2>/dev/null); fi
  got=$(families <<<"$out" 2>&1)
  [ "$got" = "$want" ] && pass "$name" || bad "$name: want '$want' got '$got'"
}

say fonts
check default - $'Cascadia Code\nNoto Sans Mono CJK TC'
check jetbrains-mono jetbrains-mono $'JetBrains Mono\nNoto Sans Mono CJK TC'
check cascadia-code cascadia-code $'Cascadia Code\nNoto Sans Mono CJK TC'
check noto noto 'Noto Sans Mono CJK TC'
check empty '' $'Cascadia Code\nNoto Sans Mono CJK TC'

say bad-value
err=$(VSCODIUM_FONT=comic bash "$GEN" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && grep -q '^\[entrypoint\] unknown VSCODIUM_FONT' <<<"$err" && pass "bad-value warns" || bad "bad-value: rc=$rc err=$err"
check bad-value-falls-back comic $'Cascadia Code\nNoto Sans Mono CJK TC'

finish
