import { ApiRequestError, type ApiEnvelope } from '../models/api';

const configuredBase = import.meta.env.VITE_API_BASE_URL as string | undefined;
export const API_BASE_URL = (configuredBase && configuredBase.replace(/\/$/, '')) || '/api/v1';

type ErrorFields = Record<string, string[]>;
type JsonObject = Record<string, unknown>;

export interface ApiRequestOptions extends RequestInit {
  token?: string | null;
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringList(value: unknown): string[] | null {
  if (Array.isArray(value)) {
    const items = value.filter((item): item is string => typeof item === 'string');
    return items.length ? items : null;
  }
  if (typeof value === 'string') {
    return [value];
  }
  return null;
}

function validationFields(payload: unknown): ErrorFields | undefined {
  if (!isObject(payload)) return undefined;
  const fields = Object.entries(payload).reduce<ErrorFields>((result, [key, value]) => {
    if (['success', 'error', 'data', 'detail', 'code'].includes(key)) return result;
    const list = stringList(value);
    if (list) result[key] = list;
    return result;
  }, {});
  return Object.keys(fields).length ? fields : undefined;
}

function firstFieldMessage(fields?: ErrorFields): string | null {
  if (!fields) return null;
  if (fields.non_field_errors?.[0]) return fields.non_field_errors[0];
  const first = Object.values(fields).find((messages) => messages.length > 0);
  return first?.[0] ?? null;
}

function errorFromPayload(payload: unknown, status: number) {
  if (isObject(payload) && payload.success === false && isObject(payload.error)) {
    const fields = validationFields(payload.error.fields);
    return {
      message: typeof payload.error.message === 'string' ? payload.error.message : firstFieldMessage(fields) || `HTTP ${status}`,
      code: typeof payload.error.code === 'string' ? payload.error.code : 'request_failed',
      fields,
    };
  }

  if (isObject(payload)) {
    const fields = validationFields(payload);
    const detail = typeof payload.detail === 'string' ? payload.detail : null;
    return {
      message: firstFieldMessage(fields) || detail || `HTTP ${status}`,
      code: typeof payload.code === 'string' ? payload.code : 'request_failed',
      fields,
    };
  }

  return { message: `HTTP ${status}`, code: 'request_failed', fields: undefined };
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

  let payload: unknown = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  const envelope = payload as ApiEnvelope<T> | null;
  if (!response.ok || envelope?.success === false) {
    const error = errorFromPayload(payload, response.status);
    throw new ApiRequestError(error.message, error.code, response.status, error.fields);
  }

  if (!envelope || envelope.data === undefined) {
    throw new ApiRequestError('Malformed API response.', 'malformed_response', response.status);
  }

  return envelope.data;
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