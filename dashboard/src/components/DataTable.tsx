import type { AdminRecord, RecordValue } from '../models/admin';
import { StatusBadge } from './StatusBadge';

function formatValue(value: RecordValue): string {
  if (value === null || value === undefined) return 'empty';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function cellFor(key: string, value: RecordValue) {
  if (['status', 'severity', 'type', 'action', 'success', 'is_active', 'is_read'].some((marker) => key.includes(marker))) {
    return <StatusBadge value={value as string | number | boolean | null} />;
  }
  const text = formatValue(value);
  return <span title={text}>{text}</span>;
}

export function DataTable({ records, selectedId, onSelect }: { records: AdminRecord[]; selectedId?: string | null; onSelect: (record: AdminRecord) => void }) {
  const columns = records[0] ? Object.keys(records[0]).slice(0, 8) : [];
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            {columns.map((column) => <th key={column}>{column}</th>)}
          </tr>
        </thead>
        <tbody>
          {records.map((record) => {
            const id = String(record.id ?? '');
            return (
              <tr key={id || JSON.stringify(record)} className={selectedId === id ? 'is-selected' : ''} onClick={() => onSelect(record)}>
                {columns.map((column) => <td key={column}>{cellFor(column, record[column])}</td>)}
              </tr>
            );
          })}
          {!records.length && (
            <tr>
              <td colSpan={Math.max(columns.length, 1)} className="empty-cell">No records match this view.</td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}