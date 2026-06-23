import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const xcstringsPath = path.resolve(__dirname, '../../Mesh/Mesh/Localizable.xcstrings');
const outDir = path.resolve(__dirname, '../src/core/l10n/locales');

const langs = ['en', 'tr', 'vi', 'id', 'es'];
const raw = JSON.parse(fs.readFileSync(xcstringsPath, 'utf8'));
const result = Object.fromEntries(langs.map((l) => [l, {}]));

for (const [key, entry] of Object.entries(raw.strings)) {
  if (!key || key.startsWith('%') || key.length < 2) continue;
  if (!entry.localizations) continue;
  for (const lang of langs) {
    const loc = entry.localizations[lang]?.stringUnit?.value;
    if (loc) result[lang][key] = loc.replace(/\%@/g, '%s').replace(/\%(\d+)\$@/g, '%$1$s');
  }
  if (!result.en[key] && entry.localizations.en?.stringUnit?.value) {
    result.en[key] = entry.localizations.en.stringUnit.value.replace(/\%@/g, '%s');
  }
}

fs.mkdirSync(outDir, { recursive: true });
for (const lang of langs) {
  const sorted = Object.fromEntries(Object.keys(result[lang]).sort().map((k) => [k, result[lang][k]]));
  fs.writeFileSync(path.join(outDir, `${lang}.json`), JSON.stringify(sorted, null, 2));
}
console.log('Extracted', Object.keys(result.en).length, 'keys per locale');
