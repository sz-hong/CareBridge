import { Icon } from './Icon';

export type ViewKey = 'overview' | 'data' | 'storage' | 'requestLogs' | 'runtimeLogs' | 'audit';

const navItems: Array<{ key: ViewKey; label: string; icon: Parameters<typeof Icon>[0]['name'] }> = [
  { key: 'overview', label: 'Overview', icon: 'overview' },
  { key: 'data', label: 'Data', icon: 'data' },
  { key: 'storage', label: 'Storage', icon: 'storage' },
  { key: 'requestLogs', label: 'Request Logs', icon: 'request' },
  { key: 'runtimeLogs', label: 'Runtime Logs', icon: 'runtime' },
  { key: 'audit', label: 'Audit', icon: 'audit' },
];

export function Sidebar({ activeView, onViewChange }: { activeView: ViewKey; onViewChange: (view: ViewKey) => void }) {
  return (
    <nav className="side-nav" aria-label="Dashboard sections">
      {navItems.map((item) => (
        <button key={item.key} className={activeView === item.key ? 'side-nav__item is-active' : 'side-nav__item'} onClick={() => onViewChange(item.key)}>
          <Icon name={item.icon} />
          <span>{item.label}</span>
        </button>
      ))}
    </nav>
  );
}