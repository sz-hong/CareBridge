import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import type { FieldSchema } from '../models/admin';
import type { FormValues } from '../viewmodels/dataTableViewModel';
import { initialValuesFromRecord } from '../viewmodels/dataTableViewModel';

export function SchemaForm({
  fields,
  record,
  submitLabel,
  onSubmit,
}: {
  fields: FieldSchema[];
  record?: Record<string, unknown> | null;
  submitLabel: string;
  onSubmit: (values: FormValues) => Promise<void> | void;
}) {
  const [values, setValues] = useState<FormValues>(() => initialValuesFromRecord(fields, record as never));
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setValues(initialValuesFromRecord(fields, record as never));
  }, [fields, record]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setIsSaving(true);
    setError(null);
    try {
      await onSubmit(values);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed.');
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <form className="schema-form" onSubmit={submit}>
      {fields.map((field) => (
        <label key={field.name} className="field-row">
          <span>{field.label}{field.required ? ' *' : ''}</span>
          {field.control === 'textarea' || field.control === 'json' ? (
            <textarea value={String(values[field.name] ?? '')} readOnly={field.readonly} onChange={(event) => setValues({ ...values, [field.name]: event.target.value })} rows={field.control === 'json' ? 5 : 3} />
          ) : field.control === 'checkbox' ? (
            <input type="checkbox" checked={Boolean(values[field.name])} disabled={field.readonly} onChange={(event) => setValues({ ...values, [field.name]: event.target.checked })} />
          ) : field.control === 'select' ? (
            <select value={String(values[field.name] ?? '')} disabled={field.readonly} onChange={(event) => setValues({ ...values, [field.name]: event.target.value })}>
              <option value="">Select</option>
              {field.choices.map((choice) => <option key={String(choice.value)} value={String(choice.value)}>{choice.label}</option>)}
            </select>
          ) : (
            <input type={field.control === 'number' ? 'number' : field.control === 'datetime' ? 'datetime-local' : field.control} value={String(values[field.name] ?? '')} readOnly={field.readonly} onChange={(event) => setValues({ ...values, [field.name]: event.target.value })} />
          )}
        </label>
      ))}
      {error && <div className="form-error">{error}</div>}
      <button className="button button--primary" disabled={isSaving}>{isSaving ? 'Saving...' : submitLabel}</button>
    </form>
  );
}