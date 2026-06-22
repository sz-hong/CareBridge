import { useOverviewViewModel } from '../viewmodels/overviewViewModel';
import { Icon } from '../components/Icon';
import { StatusBadge } from '../components/StatusBadge';

export function OverviewView({ token }: { token: string | null }) {
  const vm = useOverviewViewModel(token);
  return (
    <section className="page-grid overview-page">
      <div className="page-heading">
        <div>
          <h1>Overview</h1>
          <p>Global staff view across product tables, activity, and operational alerts.</p>
        </div>
        <button className="icon-button" onClick={vm.refresh} title="Refresh"><Icon name="refresh" /></button>
      </div>
      {vm.error && <div className="notice notice--danger">{vm.error}</div>}
      <div className="metric-strip">
        {vm.overview?.kpis.map((kpi) => (
          <div className="metric" key={kpi.label}>
            <span>{kpi.label}</span>
            <strong>{kpi.value}</strong>
            <small>{kpi.delta_24h >= 0 ? '+' : ''}{kpi.delta_24h} / 24h</small>
          </div>
        ))}
        <div className="metric">
          <span>Admin Tables</span>
          <strong>{vm.tables.length}</strong>
          <small>allow-listed</small>
        </div>
      </div>
      <div className="two-column">
        <section className="panel">
          <h2>Table Health</h2>
          <div className="compact-list">
            {vm.overview?.tables.map((table) => (
              <div className="compact-row" key={table.table}>
                <span>{table.table}</span>
                <strong>{table.count}</strong>
                <small>{table.created_24h} created</small>
              </div>
            ))}
          </div>
        </section>
        <section className="panel">
          <h2>Recent Activity</h2>
          <div className="compact-list">
            {vm.activity?.results.map((item) => (
              <div className="compact-row" key={item.id}>
                <span>{item.table}</span>
                <StatusBadge value={item.action} />
                <small>{item.actor ?? 'system'}</small>
              </div>
            ))}
          </div>
        </section>
      </div>
      <section className="panel">
        <h2>Operational Alerts</h2>
        <div className="compact-list">
          {(vm.overview?.alerts.length ? vm.overview.alerts : [{ severity: 'success', title: 'No active alerts', count: 0 }]).map((alert) => (
            <div className="compact-row" key={alert.title}>
              <StatusBadge value={alert.severity} />
              <span>{alert.title}</span>
              <strong>{alert.count}</strong>
            </div>
          ))}
        </div>
      </section>
    </section>
  );
}