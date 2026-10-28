// Print the languagepacks.json VSCodium expects in its user-data-dir:
//   ELECTRON_RUN_AS_NODE=1 /usr/share/codium/codium languagepacks.js <extensions-dir>
// VSCodium only writes this file after its first start and applies --locale on
// the next one; every RDP session starts with a fresh user-data-dir, so the
// session writes it up front instead.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const dir = process.argv[2];
const packs = {};
for (const name of fs.existsSync(dir) ? fs.readdirSync(dir).sort() : []) {
  const location = path.join(dir, name);
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(path.join(location, 'package.json'), 'utf8'));
  } catch {
    continue;
  }
  const localizations = (manifest.contributes && manifest.contributes.localizations) || [];
  const id = `${manifest.publisher}.${manifest.name}`.toLowerCase();
  for (const loc of localizations) {
    const lang = loc.languageId.toLowerCase();
    const pack = packs[lang] || (packs[lang] = { hash: '', extensions: [], translations: {}, label: '' });
    pack.extensions.push({ extensionIdentifier: { id }, version: manifest.version });
    for (const t of loc.translations || []) {
      pack.translations[t.id] = path.join(location, t.path);
    }
    pack.label = loc.localizedLanguageName || loc.languageName || lang;
  }
}
for (const pack of Object.values(packs)) {
  const md5 = crypto.createHash('md5');
  for (const e of pack.extensions) md5.update(e.extensionIdentifier.id).update(e.version);
  pack.hash = md5.digest('hex');
}
process.stdout.write(JSON.stringify(packs));
