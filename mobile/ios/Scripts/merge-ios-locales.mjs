#!/usr/bin/env node
/**
 * Merges Scripts/l10n/{ar,zh-Hans}.json into Mesh/Localizable.xcstrings
 * Run: node Scripts/merge-ios-locales.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const catalogPath = path.join(root, 'Mesh/Localizable.xcstrings');
const l10nDir = path.join(root, 'Scripts/l10n');

const LOCALES = ['ar', 'zh-Hans'];

function loadLocale(code) {
  const file = path.join(l10nDir, `${code}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`Missing locale file: ${file}`);
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function toIOSPlaceholders(value) {
  return value
    .replace(/%(\d+)\$s/g, '%$1$@')
    .replace(/%s/g, '%@');
}

function unit(value) {
  return {
    stringUnit: {
      state: 'translated',
      value: toIOSPlaceholders(value),
    },
  };
}

function mergeLocale(catalog, localeCode, translations) {
  let merged = 0;
  for (const [key, entry] of Object.entries(catalog.strings)) {
    if (!key) continue;
    const translated = translations[key];
    if (!translated) continue;

    entry.localizations ??= {};
    entry.localizations[localeCode] = unit(translated);
    merged += 1;
  }
  return merged;
}

const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
const summary = {};

for (const code of LOCALES) {
  const translations = loadLocale(code);
  summary[code] = mergeLocale(catalog, code, translations);
}

fs.writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log('Merged into Localizable.xcstrings:', summary);
