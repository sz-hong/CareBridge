import { useState } from 'react';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { DataTable } from '../components/DataTable';
import { FilterBar } from '../components/FilterBar';
import { Icon } from '../components/Icon';
import { RecordDrawer } from '../components/RecordDrawer';
import { SchemaForm } from '../components/SchemaForm';
import { useDataTableViewModel } from '../viewmodels/dataTableViewModel';

export function DataView({ token }: { token: string | null }) {
  const vm = useDataTableViewModel(token);
  const [showCreate, setShowCreate] = useState(false);
  const [deleteId, setDeleteId] = useState<string | null>(null);

  async function confirmDelete() {
    if (!deleteId) return;
    await vm.deleteRecord(deleteId);
    setDeleteId(null);
  }

  return (
    <section className="data-workspace">
      <div className="workspace-main">
        <div className="page-heading">
          <div>
            <h1>Data</h1>
            <p>Schema-driven CRUD for product tables. Identity and admin log tables remain protected.</p>
          </div>
          {vm.selectedTableInfo?.capabilities.create && <button className="button button--primary" onClick={() => setShowCreate(true)}><Icon name="plus" />Create</button>}
        </div>
        <div className="table-tabs" role="tablist">
          {vm.tables.map((table) => (
            <button key={table.table} className={vm.selectedTable === table.table ? 'table-tab is-active' : 'table-tab'} onClick={() => vm.setSelectedTable(table.table)}>
              <span>{table.display_name}</span>
              <small>{table.category}</small>
            </button>
          ))}
        </div>
        <FilterBar search={vm.search} onSearchChange={vm.setSearch} onRefresh={vm.refresh}>
          <span className="result-count">{vm.records?.count ?? 0} records</span>
          {vm.selectedTableInfo && <span className="capability-note">{vm.selectedTableInfo.capabilities.update ? 'create/update/delete' : 'read-only'}</span>}
        </FilterBar>
        {vm.error && <div className="notice notice--danger">{vm.error}</div>}
        <DataTable records={vm.records?.results ?? []} selectedId={String(vm.selectedRecord?.id ?? '')} onSelect={vm.setSelectedRecord} />
      </div>
      <RecordDrawer
        table={vm.selectedTable}
        record={vm.selectedRecord}
        fields={vm.schema?.fields ?? []}
        canUpdate={Boolean(vm.selectedTableInfo?.capabilities.update)}
        canDelete={Boolean(vm.selectedTableInfo?.capabilities.delete)}
        token={token}
        onClose={() => vm.setSelectedRecord(null)}
        onUpdate={vm.updateRecord}
        onDelete={(id) => {
          setDeleteId(id);
          return Promise.resolve();
        }}
      />
      {showCreate && vm.schema && (
        <div className="dialog-backdrop" role="presentation">
          <section className="create-dialog" role="dialog" aria-modal="true">
            <div className="drawer-header">
              <div><span className="eyebrow">{vm.selectedTable}</span><h2>Create Record</h2></div>
              <button className="icon-button" onClick={() => setShowCreate(false)}><Icon name="close" /></button>
            </div>
            <SchemaForm
              fields={vm.schema.fields}
              submitLabel="Create record"
              token={token}
              formId={`${vm.selectedTable}:create`}
              onSubmit={async (values) => {
                await vm.createRecord(values);
                setShowCreate(false);
              }}
            />
          </section>
        </div>
      )}
      {deleteId && (
        <ConfirmDialog
          title="Soft delete record"
          body="The backend will write a tombstone audit entry and hide this record from dashboard views. The database row is not physically deleted."
          confirmLabel="Soft delete"
          onConfirm={() => void confirmDelete()}
          onCancel={() => setDeleteId(null)}
        />
      )}
    </section>
  );
}