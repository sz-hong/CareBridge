import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { DashboardSession } from '../models/auth';
import { authService } from '../services/authService';

class MemoryStorage {
  private values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
  removeItem(key: string) { this.values.delete(key); }
  clear() { this.values.clear(); }
}

beforeEach(() => {
  Object.defineProperty(globalThis, 'sessionStorage', { value: new MemoryStorage(), configurable: true });
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('authService session storage', () => {
  it('saves, loads, and clears dashboard sessions', () => {
    const session: DashboardSession = {
      accessToken: 'access',
      refreshToken: 'refresh',
      user: { id: 'u1', email: 'staff@example.com', is_staff: true },
    };

    authService.saveSession(session);
    expect(authService.loadSession()).toEqual(session);
    expect(authService.getAccessToken()).toBe('access');

    authService.logout();
    expect(authService.loadSession()).toBeNull();
  });
});

describe('authService login', () => {
  it('stores the session only after staff admin access is verified', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          success: true,
          data: {
            user: { id: 'u1', email: 'staff@example.com' },
            tokens: { access: 'access-token', refresh: 'refresh-token' },
          },
        }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ success: true, data: { kpis: [], tables: [], alerts: [] } }),
      });
    vi.stubGlobal('fetch', fetchMock);

    const session = await authService.login('staff@example.com', 'password123');

    expect(session.accessToken).toBe('access-token');
    expect(authService.getAccessToken()).toBe('access-token');
    expect(fetchMock).toHaveBeenNthCalledWith(2, '/api/v1/admin/overview/', expect.objectContaining({ headers: expect.any(Headers) }));
    const headers = fetchMock.mock.calls[1][1].headers as Headers;
    expect(headers.get('Authorization')).toBe('Bearer access-token');
  });

  it('shows a staff access error and does not persist non-staff sessions', async () => {
    vi.stubGlobal('fetch', vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({
          success: true,
          data: {
            user: { id: 'u2', email: 'member@example.com' },
            tokens: { access: 'member-access', refresh: 'member-refresh' },
          },
        }),
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 403,
        json: async () => ({ success: false, error: { code: 'permission_denied', message: 'Staff access is required.' } }),
      }));

    await expect(authService.login('member@example.com', 'password123')).rejects.toThrow('Staff access is required for the dashboard.');
    expect(authService.loadSession()).toBeNull();
  });
});
