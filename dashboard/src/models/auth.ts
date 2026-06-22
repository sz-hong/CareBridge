export interface DashboardUser {
  id: string;
  email: string;
  name?: string;
  is_staff?: boolean;
  role?: string;
}

export interface AuthTokens {
  access: string;
  refresh: string;
}

export interface AuthResponse {
  user: DashboardUser;
  tokens: AuthTokens;
}

export interface DashboardSession {
  user: DashboardUser;
  accessToken: string;
  refreshToken: string;
}