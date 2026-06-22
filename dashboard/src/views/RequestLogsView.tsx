import { FilterBar } from '../components/FilterBar';
import { StatusBadge } from '../components/StatusBadge';
import { useRequestLogsViewModel } from '../viewmodels/logsViewModel';

export function RequestLogsView({ token }: { token: string | null }) {
  const vm = useRequestLogsViewModel(token);
  return (
    <section className="page-grid">
      <div className="page-heading"><div><h1>Request Logs</h1><p>Structured request monitor for `/api/v1/*` traffic.</p></div></div>
      <FilterBar search={vm.search} onSearchChange={vm.setSearch} onRefresh={vm.refresh}>
        <select value={vm.method} onChange={(event) => vm.setMethod(event.target.value)}>
          <option value="">Any method</option><option>GET</option><option>POST</option><option>PATCH</option><option>DELETE</option>
        </select>
        <select value={vm.statusClass} onChange={(event) => vm.setStatusClass(event.target.value)}>
          <option value="">Any status</option><option value="2xx">2xx</option><option value="4xx">4xx</option><option value="5xx">5xx</option>
        </select>
      </FilterBar>
      {vm.error && <div className="notice notice--danger">{vm.error}</div>}
      <div className="table-wrap"><table className="data-table"><thead><tr><th>Time</th><th>Method</th><th>Status</th><th>Path</th><th>User</th><th>Duration</th></tr></thead><tbody>
        {vm.logs?.results.map((log) => <tr key={log.id}><td>{log.created_at}</td><td>{log.method}</td><td><StatusBadge value={log.status_class} /></td><td>{log.path}{log.query ? `?${log.query}` : ''}</td><td>{log.user_email ?? 'anonymous'}</td><td>{log.duration_ms} ms</td></tr>)}
      </tbody></table></div>
    </section>
  );
}