import { useMemo } from 'react';
import type { Language } from '@/core/types';
import { enCatalog } from './catalog-en';
import en from './locales/en.json';
import tr from './locales/tr.json';
import vi from './locales/vi.json';
import id from './locales/id.json';
import es from './locales/es.json';

type Catalog = Record<string, string>;

/** Full English strings from iOS extract + hand-maintained catalog fallbacks. */
const enBase: Catalog = {
  ...enCatalog,
  ...en,
  'transfer.proof.copy.tx': 'Copy transaction ID',
};

const catalogs: Record<Language, Catalog> = {
  en: enBase,
  tr: { ...enBase, ...tr },
  vi: { ...enBase, ...vi },
  id: { ...enBase, ...id },
  es: { ...enBase, ...es },
};

export function translate(lang: Language, key: string, ...args: (string | number)[]): string {
  let text = catalogs[lang]?.[key] ?? enBase[key] ?? key;
  args.forEach((arg, i) => {
    text = text.replace(`%${i + 1}$s`, String(arg)).replace('%s', String(arg));
  });
  return text;
}

export function useT(lang: Language) {
  return useMemo(
    () => ({
      t: (key: string, ...args: (string | number)[]) => translate(lang, key, ...args),
      lang,
    }),
    [lang],
  );
}

export { L10nKeys } from './keys';
