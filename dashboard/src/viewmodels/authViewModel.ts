import { useState } from 'react';
import type { DashboardSession } from '../models/auth';
import { authService } from '../services/authService';

export function useAuthViewModel() {
  const [session, setSession] = useState<DashboardSession | null>(() => authService.loadSession());
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function login(email: string, password: string) {
    setIsLoading(true);
    setError(null);
    try {
      const next = await authService.login(email, password);
      setSession(next);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed.');
    } finally {
      setIsLoading(false);
    }
  }

  function logout() {
    authService.logout();
    setSession(null);
  }

  return { session, token: session?.accessToken ?? null, user: session?.user ?? null, isLoading, error, login, logout };
}