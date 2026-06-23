import { Buffer } from 'buffer';

/** TronWeb and crypto deps expect Node globals in the extension UI. */
if (typeof globalThis.Buffer === 'undefined') {
  globalThis.Buffer = Buffer;
}

if (typeof globalThis.global === 'undefined') {
  globalThis.global = globalThis;
}
