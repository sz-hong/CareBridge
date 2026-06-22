import { ApiRequestError, type ApiEnvelope } from '../models/api';

const configuredBase = import.meta.env.VITE_API_BASE_URL as string | undefined;
export const API_BASE_URL = (configuredBase && configuredBase.replace(/\/$/, '')) || '/api/v1';

export interface ApiRequestOptions extends RequestInit {
  token?: string | null;
}

export async function apiRequest<T>(path: string, options: ApiRequestOptions = {}): Promise<T> {
  const headers = new Headers(options.headers);
  const token = options.token;

  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  if (!headers.has('Accept')) {
    headers.set('Accept', 'application/json');
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers,
  });

  let payload: ApiEnvelope<T> | null = null;
  try {
    payload = (await response.json()) as ApiEnvelope<T>;
  } catch {
    payload = null;
  }

  if (!response.ok || payload?.success === false) {
    const error = payload?.error;
    throw new ApiRequestError(
      error?.message || `HTTP ${response.status}`,
      error?.code || 'request_failed',
      response.status,
      error?.fields,
    );
  }

  if (!payload || payload.data === undefined) {
    throw new ApiRequestError('Malformed API response.', 'malformed_response', response.status);
  }

  return payload.data;
}

export type QueryParams = Record<string, string | number | boolean | null | undefined>;

export function toQuery(params: QueryParams): string {
  const query = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      query.set(key, String(value));
    }
  });
  const text = query.toString();
  return text ? `?${text}` : '';
}