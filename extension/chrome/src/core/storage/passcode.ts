import { storageGet, storageSet, storageRemove, StorageKeys } from './storage';

const MIN_PASSWORD_LENGTH = 8;
const MAX_PASSWORD_LENGTH = 128;

async function sha256(data: BufferSource): Promise<ArrayBuffer> {
  return crypto.subtle.digest('SHA-256', data);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function bufferToHex(buffer: ArrayBuffer): string {
  return bytesToHex(new Uint8Array(buffer));
}

function hexToBuffer(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}

function randomSalt(): Uint8Array {
  const salt = new Uint8Array(32);
  crypto.getRandomValues(salt);
  return salt;
}

async function hashPasscode(passcode: string, salt: Uint8Array): Promise<string> {
  const combined = new Uint8Array(salt.length + passcode.length);
  combined.set(salt);
  combined.set(new TextEncoder().encode(passcode), salt.length);
  const digest = await sha256(combined.buffer.slice(combined.byteOffset, combined.byteOffset + combined.byteLength));
  return bufferToHex(digest);
}

export const PasscodeStore = {
  minLength: MIN_PASSWORD_LENGTH,
  maxLength: MAX_PASSWORD_LENGTH,

  isValidPassword(password: string): boolean {
    const length = password.length;
    return length >= MIN_PASSWORD_LENGTH && length <= MAX_PASSWORD_LENGTH;
  },

  async isEnabled(): Promise<boolean> {
    const enabled = await storageGet<boolean>(StorageKeys.passcodeEnabled);
    const hash = await storageGet<string>(StorageKeys.passcodeHash);
    return !!enabled && !!hash;
  },

  async setPasscode(passcode: string): Promise<boolean> {
    if (!this.isValidPassword(passcode)) return false;
    const salt = randomSalt();
    const hash = await hashPasscode(passcode, salt);
    await storageSet(StorageKeys.passcodeHash, hash);
    await storageSet(StorageKeys.passcodeSalt, bytesToHex(salt));
    await storageSet(StorageKeys.passcodeEnabled, true);
    return true;
  },

  async verify(passcode: string): Promise<boolean> {
    if (!passcode) return false;
    const storedHash = await storageGet<string>(StorageKeys.passcodeHash);
    const saltHex = await storageGet<string>(StorageKeys.passcodeSalt);
    if (!storedHash || !saltHex) return false;
    const hash = await hashPasscode(passcode, hexToBuffer(saltHex));
    return hash === storedHash;
  },

  async clear(): Promise<void> {
    await storageRemove(StorageKeys.passcodeEnabled);
    await storageRemove(StorageKeys.passcodeHash);
    await storageRemove(StorageKeys.passcodeSalt);
  },
};
