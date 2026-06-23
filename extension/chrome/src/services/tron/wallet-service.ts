import { mnemonicToSeedSync, generateMnemonic, validateMnemonic } from '@scure/bip39';
import { wordlist as englishWordlist } from '@scure/bip39/wordlists/english';
import { HDKey } from '@scure/bip32';
import { TronWeb } from 'tronweb';
import { CONFIG } from '@/core/config';
import { storageGet, StorageKeys } from '@/core/storage/storage';
import { WalletRegistry } from '@/core/storage/wallet-registry';

const tronWeb = new TronWeb({ fullHost: CONFIG.tronGridBase });

export function receiveDerivationPath(index: number): string {
  return `m/44'/195'/0'/0/${index}`;
}

export function relayDerivationPath(index: number): string {
  return `m/44'/195'/0'/1/${index}`;
}

function derivePrivateKeyHex(mnemonic: string, path: string, passphrase = ''): string {
  const seed = mnemonicToSeedSync(mnemonic, passphrase);
  const hd = HDKey.fromMasterSeed(seed);
  const child = hd.derive(path);
  if (!child.privateKey) throw new Error('Could not derive private key');
  return Array.from(child.privateKey)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function addressFromPrivateKey(privateKeyHex: string): string {
  return tronWeb.address.fromPrivateKey(privateKeyHex) as string;
}

export const WalletService = {
  createWallet(): { mnemonic: string[]; address: string } {
    const phrase = generateMnemonic(englishWordlist);
    const words = phrase.split(' ');
    const address = this.deriveReceiveAddress(words, 0);
    return { mnemonic: words, address };
  },

  importMnemonic(words: string[], passphrase = ''): string {
    const mnemonic = words.map((w) => w.trim().toLowerCase()).filter(Boolean).join(' ');
    if (!validateMnemonic(mnemonic, englishWordlist)) throw new Error('Invalid recovery phrase');
    return this.deriveReceiveAddress(words, 0, passphrase);
  },

  importPrivateKey(hex: string): string {
    const normalized = this.normalizePrivateKeyInput(hex);
    if (normalized.length !== 64) throw new Error('Invalid private key. Use 64 hex characters.');
    return addressFromPrivateKey(normalized);
  },

  normalizePrivateKeyInput(hex: string): string {
    return hex.replace(/^0x/i, '').replace(/\s/g, '').toLowerCase();
  },

  deriveReceiveAddress(words: string[], index: number, passphrase = ''): string {
    const mnemonic = words.map((w) => w.trim().toLowerCase()).filter(Boolean).join(' ');
    const pk = derivePrivateKeyHex(mnemonic, receiveDerivationPath(index), passphrase);
    return addressFromPrivateKey(pk);
  },

  deriveRelayAddress(words: string[], index: number, passphrase = ''): string {
    const mnemonic = words.map((w) => w.trim().toLowerCase()).filter(Boolean).join(' ');
    const pk = derivePrivateKeyHex(mnemonic, relayDerivationPath(index), passphrase);
    return addressFromPrivateKey(pk);
  },

  async getPrivateKeyHex(walletId: string, derivationPath: string): Promise<string> {
    const pkHex = await storageGet<string>(StorageKeys.privateKey(walletId));
    if (pkHex) return pkHex.replace(/^0x/i, '');
    const mnemonic = await storageGet<string>(StorageKeys.mnemonic(walletId));
    if (!mnemonic) throw new Error('Wallet credentials not found');
    const passphrase = (await storageGet<string>(StorageKeys.passphrase(walletId))) ?? '';
    return derivePrivateKeyHex(mnemonic, derivationPath, passphrase);
  },

  async supportsHDFeatures(walletId?: string): Promise<boolean> {
    const id = walletId ?? (await WalletRegistry.getActiveWalletId());
    if (!id) return false;
    const wallet = await WalletRegistry.getWallet(id);
    return wallet?.importKind === 'mnemonic';
  },
};

export const WalletCredentials = {
  async resolve(walletId?: string): Promise<{
    walletId: string;
    address: string;
    mnemonic: string[] | null;
    importKind: 'mnemonic' | 'privateKey';
    derivationPath: string;
  }> {
    const id = walletId ?? (await WalletRegistry.getActiveWalletId());
    if (!id) throw new Error('No active wallet');
    const wallet = await WalletRegistry.getWallet(id);
    if (!wallet) throw new Error('Wallet not found');
    const mnemonicStr = await storageGet<string>(StorageKeys.mnemonic(id));
    const mnemonic = mnemonicStr ? mnemonicStr.split(' ').filter(Boolean) : null;
    return {
      walletId: id,
      address: wallet.address,
      mnemonic,
      importKind: wallet.importKind,
      derivationPath: receiveDerivationPath(0),
    };
  },

  async signingKey(derivationPath: string, walletId?: string): Promise<string> {
    const resolved = await this.resolve(walletId);
    return WalletService.getPrivateKeyHex(resolved.walletId, derivationPath);
  },
};
