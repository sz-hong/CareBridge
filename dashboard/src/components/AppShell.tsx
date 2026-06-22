import type { ReactNode } from 'react';
import type { DashboardUser } from '../models/auth';
import { Icon } from './Icon';
import { Sidebar, type ViewKey } from './Sidebar';
import { Topbar } from './Topbar';

interface AppShellProps {
  activeView: ViewKey;
  onViewChange: (view: ViewKey) => void;
  user: DashboardUser;
  onLogout: () => void;
  children: ReactNode;
}

export function AppShell({ activeView, onViewChange, user, onLogout, children }: AppShellProps) {
  return (
    <div className="app-shell">
      <aside className="shell-sidebar">
        <div className="brand-lockup">
          <div className="brand-mark"><Icon name="shield" /></div>
          <div>
            <strong>CareBridge</strong>
            <span>Admin Console</span>
          </div>
        </div>
        <Sidebar activeView={activeView} onViewChange={onViewChange} />
      </aside>
      <main className="shell-main">
        <Topbar user={user} onLogout={onLogout} />
        <div className="view-frame">{children}</div>
      </main>
    </div>
  );
}