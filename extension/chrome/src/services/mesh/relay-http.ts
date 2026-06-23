import { CONFIG } from '@/core/config';
import type { SendStatusResponse } from '@/core/types';

function relayUrl(path: string): string {
  return `${CONFIG.relayUrl.replace(/\/$/, '')}${path}`;
}

function authHeaders(): Record<string, string> {
  return CONFIG.relayAuthSecret
    ? { Authorization: `Bearer ${CONFIG.relayAuthSecret}` }
    : {};
}

export async function relayFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(relayUrl(path), {
    ...options,
    headers: {
      Accept: 'application/json',
      ...authHeaders(),
      ...(options.headers as Record<string, string>),
    },
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error((data as { message?: string }).message ?? `Relay error ${response.status}`);
  }
  return data as T;
}

export async function fetchSendStatus(id: string): Promise<SendStatusResponse | null> {
  try {
    return await relayFetch<SendStatusResponse>(`/v1/send-status?id=${encodeURIComponent(id)}`);
  } catch {
    return null;
  }
}

export async function continueQueuedSend(id: string, resumeJSON?: string): Promise<void> {
  let body: object = { id };
  if (resumeJSON) {
    try {
      body = { id, ...JSON.parse(resumeJSON) };
    } catch {
      body = { id };
    }
  }
  await relayFetch('/v1/continue-queued-send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}
