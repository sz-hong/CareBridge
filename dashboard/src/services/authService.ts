import type { AuthResponse, DashboardSession } from '../models/auth';
import { apiRequest } from './apiClient';

const ACCESS_KEY = 'carebridge.dashboard.access';
const REFRESH_KEY = 'carebridge.dashboard.refresh';
const USER_KEY = 'carebridge.dashboard.user';

export const authService = {
  async login(email: string, password: string): Promise<DashboardSession> {
    const data = await apiRequest<AuthResponse>('/auth/login/', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });
    const session = {
      user: data.user,
      accessToken: data.tokens.access,
      refreshToken: data.tokens.refresh,
    };
    this.saveSession(session);
    return session;
  },

  saveSession(session: DashboardSession): void {
    sessionStorage.setItem(ACCESS_KEY, session.accessToken);
    sessionStorage.setItem(REFRESH_KEY, session.refreshToken);
    sessionStorage.setItem(USER_KEY, JSON.stringify(session.user));
  },

  loadSession(): DashboardSession | null {
    const accessToken = sessionStorage.getItem(ACCESS_KEY);
    const refreshToken = sessionStorage.getItem(REFRESH_KEY);
    const rawUser = sessionStorage.getItem(USER_KEY);
    if (!accessToken || !refreshToken || !rawUser) {
      return null;
    }
    try {
      return { accessToken, refreshToken, user: JSON.parse(rawUser) };
    } catch {
      this.logout();
      return null;
    }
  },

  getAccessToken(): string | null {
    return sessionStorage.getItem(ACCESS_KEY);
  },

  logout(): void {
    sessionStorage.removeItem(ACCESS_KEY);
    sessionStorage.removeItem(REFRESH_KEY);
    sessionStorage.removeItem(USER_KEY);
  },
};