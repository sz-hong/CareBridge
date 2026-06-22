import { useState } from 'react';
import type { AdminRecord, FieldSchema } from '../models/admin';
import { initialValuesFromRecord } from '../viewmodels/dataTableViewModel';
import { Icon } from './Icon';
import { SchemaForm } from './SchemaForm';
import { StatusBadge } from './StatusBadge';

export function RecordDrawer({
  table,
  record,
  fields,
  canUpdate,
  canDelete,
  onClose,
  onUpdate,
  onDelete,
}: {
  table: string;
  record: AdminRecord | null;
  fields: FieldSchema[];
  canUpdate: boolean;
  canDelete: boolean;
  onClose: () => void;
  onUpdate: (id: string, values: ReturnType<typeof initialValuesFromRecord>) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}) {
  const [mode, setMode] = useState<'detail' | 'edit'>('detail');
  if (!record) {
    return <aside className="record-drawer"><div className="drawer-empty">Select a record</div></aside>;
  }
  const id = String(record.id ?? '');
  return (
    <aside className="record-drawer">
      <div className="drawer-header">
        <div>
          <span className="eyebrow">{table}</span>
          <h2>{id.slice(0, 8) || 'Record detail'}</h2>
        </div>
        <button className="icon-button" onClick={onClose} title="Close"><Icon name="close" /></button>
      </div>
      <div className="drawer-actions">
        {canUpdate && <button className="button" onClick={() => setMode(mode === 'edit' ? 'detail' : 'edit')}><Icon name="edit" />{mode === 'edit' ? 'Detail' : 'Edit'}</button>}
        {canDelete && <button className="button button--danger" onClick={() => onDelete(id)}><Icon name="trash" />Delete</button>}
      </div>
      {mode === 'edit' ? (
        <SchemaForm fields={fields} record={record} submitLabel="Update record" onSubmit={(values) => onUpdate(id, values)} />
      ) : (
        <dl className="record-fields">
          {Object.entries(record).map(([key, value]) => (
            <div key={key}>
              <dt>{key}</dt>
              <dd>{key.includes('status') || key.includes('type') ? <StatusBadge value={value as never} /> : typeof value === 'object' && value !== null ? JSON.stringify(value) : String(value ?? 'empty')}</dd>
            </div>
          ))}
        </dl>
      )}
    </aside>
  );
}