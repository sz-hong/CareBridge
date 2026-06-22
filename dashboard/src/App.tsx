import { useState } from 'react';
import { AppShell } from './components/AppShell';
import type { ViewKey } from './components/Sidebar';
import { useAuthViewModel } from './viewmodels/authViewModel';
import { AuditView } from './views/AuditView';
import { DataView } from './views/DataView';
import { LoginView } from './views/LoginView';
import { OverviewView } from './views/OverviewView';
import { RequestLogsView } from './views/RequestLogsView';
import { RuntimeLogsView } from './views/RuntimeLogsView';
import { StorageView } from './views/StorageView';

function renderView(activeView: ViewKey, token: string | null) {
  switch (activeView) {
    case 'overview':
      return <OverviewView token={token} />;
    case 'storage':
      return <StorageView token={token} />;
    case 'requestLogs':
      return <RequestLogsView token={token} />;
    case 'runtimeLogs':
      return <RuntimeLogsView token={token} />;
    case 'audit':
      return <AuditView token={token} />;
    case 'data':
    default:
      return <DataView token={token} />;
  }
}

export function App() {
  const auth = useAuthViewModel();
  const [activeView, setActiveView] = useState<ViewKey>('data');

  if (!auth.session || !auth.user) {
    return <LoginView onLogin={auth.login} isLoading={auth.isLoading} error={auth.error} />;
  }

  return (
    <AppShell activeView={activeView} onViewChange={setActiveView} user={auth.user} onLogout={auth.logout}>
      {renderView(activeView, auth.token)}
    </AppShell>
  );
}