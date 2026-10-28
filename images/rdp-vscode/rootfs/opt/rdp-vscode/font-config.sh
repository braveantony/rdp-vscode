#!/usr/bin/env bash
# Print a fontconfig file that maps "monospace" to the font picked by
# VSCODIUM_FONT. VSCodium's default editor and terminal font falls through to
# monospace, so this changes the default without touching anyone's settings.json.
# CJK glyphs fall back to Noto Sans Mono CJK TC. The binding must be strong: a
# weak <prefer> loses to the zh_TW locale, which pulls Noto CJK ahead of it.
set -eu

cjk="Noto Sans Mono CJK TC"
case ${VSCODIUM_FONT:-jetbrains-mono} in
  jetbrains-mono) first="JetBrains Mono" ;;
  cascadia-code) first="Cascadia Code" ;;
  noto) first="" ;;
  *)
    echo "[entrypoint] unknown VSCODIUM_FONT: $VSCODIUM_FONT (want jetbrains-mono, cascadia-code or noto); using jetbrains-mono" >&2
    first="JetBrains Mono" ;;
esac

cat <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test qual="any" name="family"><string>monospace</string></test>
    <edit name="family" mode="prepend" binding="strong">
${first:+      <string>$first</string>
}      <string>$cjk</string>
    </edit>
  </match>
</fontconfig>
XML
