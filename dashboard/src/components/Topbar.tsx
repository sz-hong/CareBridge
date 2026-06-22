import type { DashboardUser } from '../models/auth';

export function Topbar({ user, onLogout }: { user: DashboardUser; onLogout: () => void }) {
  return (
    <header className="topbar">
      <div>
        <span className="topbar__label">Environment</span>
        <strong>Dashboard tunnel: 3000</strong>
      </div>
      <div className="topbar__right">
        <span className="health-dot" aria-label="API online" />
        <span className="topbar__account">{user.email}</span>
        <button className="button button--ghost" onClick={onLogout}>Logout</button>
      </div>
    </header>
  );
}