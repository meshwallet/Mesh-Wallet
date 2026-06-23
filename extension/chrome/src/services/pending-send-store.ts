import type { PendingSendRecord } from '@/core/types';
import { storageGet, storageSet, StorageKeys } from '@/core/storage/storage';

let writeChain: Promise<void> = Promise.resolve();

function serializedWrite<T>(fn: () => Promise<T>): Promise<T> {
  const result = writeChain.then(fn);
  writeChain = result.then(
    () => undefined,
    () => undefined,
  );
  return result;
}

export const PendingSendStore = {
  async getAll(): Promise<PendingSendRecord[]> {
    return (await storageGet<PendingSendRecord[]>(StorageKeys.pendingSends)) ?? [];
  },

  async save(records: PendingSendRecord[]): Promise<void> {
    await serializedWrite(async () => {
      await storageSet(StorageKeys.pendingSends, records);
    });
  },

  async upsert(record: PendingSendRecord): Promise<void> {
    await serializedWrite(async () => {
      const all = await storageGet<PendingSendRecord[]>(StorageKeys.pendingSends) ?? [];
      const idx = all.findIndex((r) => r.id === record.id);
      if (idx >= 0) all[idx] = record;
      else all.push(record);
      await storageSet(StorageKeys.pendingSends, all);
    });
  },

  async mutate(
    id: string,
    mutate: (record: PendingSendRecord) => void,
  ): Promise<PendingSendRecord | null> {
    return serializedWrite(async () => {
      const all = await storageGet<PendingSendRecord[]>(StorageKeys.pendingSends) ?? [];
      const idx = all.findIndex((r) => r.id === id);
      if (idx < 0) return null;
      mutate(all[idx]!);
      await storageSet(StorageKeys.pendingSends, all);
      return all[idx]!;
    });
  },

  async remove(id: string): Promise<void> {
    await serializedWrite(async () => {
      const all = (await storageGet<PendingSendRecord[]>(StorageKeys.pendingSends)) ?? [];
      await storageSet(StorageKeys.pendingSends, all.filter((r) => r.id !== id));
    });
  },
};
