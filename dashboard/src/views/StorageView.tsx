import { FilterBar } from '../components/FilterBar';
import { StatusBadge } from '../components/StatusBadge';
import { useStorageViewModel } from '../viewmodels/storageViewModel';

export function StorageView({ token }: { token: string | null }) {
  const vm = useStorageViewModel(token);
  return (
    <section className="page-grid">
      <div className="page-heading"><div><h1>Storage</h1><p>Configured bucket browser with linked-record and orphan detection.</p></div></div>
      <FilterBar onRefresh={vm.refresh}>
        <input value={vm.prefix} onChange={(event) => vm.setPrefix(event.target.value)} placeholder="prefix" />
        <label className="inline-check"><input type="checkbox" checked={vm.orphanOnly} onChange={(event) => vm.setOrphanOnly(event.target.checked)} /> Orphans only</label>
      </FilterBar>
      {vm.error && <div className="notice notice--danger">{vm.error}</div>}
      <div className="table-wrap"><table className="data-table"><thead><tr><th>Object</th><th>Size</th><th>Type</th><th>Linked Table</th><th>State</th><th>Action</th></tr></thead><tbody>
        {vm.objects?.results.map((object) => <tr key={object.object_key}><td>{object.object_key}</td><td>{object.size ?? '--'}</td><td>{object.content_type ?? '--'}</td><td>{object.linked_table ?? '--'}</td><td><StatusBadge value={object.orphan ? 'orphan' : 'linked'} /></td><td><button className="button" onClick={() => void vm.preview(object)}>{object.previewable ? 'Preview' : 'Download'}</button></td></tr>)}
      </tbody></table></div>
    </section>
  );
}