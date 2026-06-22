import { FilterBar } from '../components/FilterBar';
import { StatusBadge } from '../components/StatusBadge';
import { useRuntimeLogsViewModel } from '../viewmodels/logsViewModel';

export function RuntimeLogsView({ token }: { token: string | null }) {
  const vm = useRuntimeLogsViewModel(token);
  return (
    <section className="page-grid">
      <div className="page-heading"><div><h1>Runtime Logs</h1><p>Allow-listed raw log tail for runtime and API error streams.</p></div></div>
      <FilterBar onRefresh={vm.refresh}>
        <select value={vm.stream} onChange={(event) => vm.setStream(event.target.value)}>
          <option value="runtime">runtime</option>
          <option value="api-errors">api-errors</option>
        </select>
      </FilterBar>
      {vm.error && <div className="notice notice--danger">{vm.error}</div>}
      <div className="log-console">
        {vm.data?.lines.map((line, index) => <div className="log-line" key={`${line.timestamp}-${index}`}><span>{line.timestamp ?? '--'}</span><StatusBadge value={line.level} /><code>{line.message}</code></div>)}
      </div>
    </section>
  );
}