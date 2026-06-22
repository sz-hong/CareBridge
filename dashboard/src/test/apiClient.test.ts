import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiRequestError } from '../models/api';
import { apiRequest, toQuery } from '../services/apiClient';

afterEach(() => {
  vi.restoreAllMocks();
});

describe('apiRequest', () => {
  it('adds bearer token and unwraps successful envelopes', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ success: true, data: { value: 42 } }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const data = await apiRequest<{ value: number }>('/admin/overview/', { token: 'abc' });

    expect(data.value).toBe(42);
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/admin/overview/', expect.objectContaining({ headers: expect.any(Headers) }));
    const headers = fetchMock.mock.calls[0][1].headers as Headers;
    expect(headers.get('Authorization')).toBe('Bearer abc');
  });

  it('throws structured API errors', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 403,
      json: async () => ({ success: false, error: { code: 'permission_denied', message: 'Staff access is required.' } }),
    }));

    await expect(apiRequest('/admin/overview/')).rejects.toMatchObject({
      name: 'ApiRequestError',
      code: 'permission_denied',
      status: 403,
    } satisfies Partial<ApiRequestError>);
  });
});

describe('toQuery', () => {
  it('omits empty values and encodes the rest', () => {
    expect(toQuery({ page: 1, search: 'care log', empty: '', none: null })).toBe('?page=1&search=care+log');
  });
});