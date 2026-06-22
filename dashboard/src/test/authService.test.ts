import { beforeEach, describe, expect, it } from 'vitest';
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