import { FilterBar } from '../components/FilterBar';
import { StatusBadge } from '../components/StatusBadge';
import { useAuditViewModel } from '../viewmodels/auditViewModel';

export function AuditView({ token }: { token: string | null }) {
  const vm = useAuditViewModel(token);
  return (
    <section className="page-grid">
      <div className="page-heading"><div><h1>Audit</h1><p>Admin mutation trail for create, update, delete, upload, preview, and download actions.</p></div></div>
      <FilterBar search={vm.search} onSearchChange={vm.setSearch} onRefresh={vm.refresh}>
        <input value={vm.table} onChange={(event) => vm.setTable(event.target.value)} placeholder="table" />
        <select value={vm.action} onChange={(event) => vm.setAction(event.target.value)}>
          <option value="">Any action</option><option value="create">create</option><option value="update">update</option><option value="delete">delete</option><option value="upload">upload</option><option value="presign_preview">preview</option><option value="presign_download">download</option>
        </select>
      </FilterBar>
      {vm.error && <div className="notice notice--danger">{vm.error}</div>}
      <div className="table-wrap"><table className="data-table"><thead><tr><th>Time</th><th>Action</th><th>Table</th><th>Record</th><th>Actor</th><th>Metadata</th></tr></thead><tbody>
        {vm.logs?.results.map((log) => <tr key={log.id}><td>{log.created_at}</td><td><StatusBadge value={log.action} /></td><td>{log.table}</td><td>{log.record_id}</td><td>{log.actor_email ?? 'system'}</td><td>{JSON.stringify(log.metadata)}</td></tr>)}
      </tbody></table></div>
    </section>
  );
}