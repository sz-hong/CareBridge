import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import type { FieldSchema } from '../models/admin';
import { adminService } from '../services/adminService';
import { Icon } from './Icon';
import type { FormValues } from '../viewmodels/dataTableViewModel';
import { initialValuesFromRecord } from '../viewmodels/dataTableViewModel';
import {
  formModeForField,
  inputTypeForField,
  jsonRowsFromValue,
  jsonRowsToFormValue,
  type JsonEditorRow,
} from './schemaFormHelpers';

function FieldMeta({ field }: { field: FieldSchema }) {
  return (
    <span className="field-meta">
      <span>{field.name}</span>
      {field.required && <strong>Required</strong>}
    </span>
  );
}

function JsonObjectEditor({
  value,
  disabled,
  resetKey,
  onChange,
}: {
  value: string | boolean | undefined;
  disabled: boolean;
  resetKey: string;
  onChange: (value: string) => void;
}) {
  const [rows, setRows] = useState<JsonEditorRow[]>(() => jsonRowsFromValue(value));

  useEffect(() => {
    setRows(jsonRowsFromValue(value));
  }, [resetKey]);

  function updateRows(nextRows: JsonEditorRow[]) {
    setRows(nextRows);
    onChange(jsonRowsToFormValue(nextRows));
  }

  return (
    <div className="json-editor">
      <div className="json-editor__head">
        <span>Key</span>
        <span>Value</span>
      </div>
      {rows.map((row, index) => (
        <div className="json-editor__row" key={`${resetKey}-${index}`}>
          <input
            value={row.key}
            disabled={disabled}
            placeholder="field_name"
            onChange={(event) => {
              const nextRows = [...rows];
              nextRows[index] = { ...row, key: event.target.value };
              updateRows(nextRows);
            }}
          />
          <input
            value={row.value}
            disabled={disabled}
            placeholder="value"
            onChange={(event) => {
              const nextRows = [...rows];
              nextRows[index] = { ...row, value: event.target.value };
              updateRows(nextRows);
            }}
          />
          <button
            className="icon-button json-editor__remove"
            type="button"
            disabled={disabled || rows.length === 1}
            onClick={() => updateRows(rows.filter((_, rowIndex) => rowIndex !== index))}
            title="Remove row"
          >
            <Icon name="close" />
          </button>
        </div>
      ))}
      <button
        className="button button--ghost json-editor__add"
        type="button"
        disabled={disabled}
        onClick={() => updateRows([...rows, { key: '', value: '' }])}
      >
        Add field
      </button>
    </div>
  );
}

function RelationLookupField({
  field,
  token,
  value,
  disabled,
  onChange,
}: {
  field: FieldSchema;
  token?: string | null;
  value: string;
  disabled: boolean;
  onChange: (value: string) => void;
}) {
  const [search, setSearch] = useState('');
  const [options, setOptions] = useState<Array<{ id: string; label: string }>>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const resource = field.relation?.resource;

  useEffect(() => {
    if (!token || !resource || disabled) return;
    let cancelled = false;
    const timer = window.setTimeout(() => {
      setIsLoading(true);
      setError(null);
      adminService.lookup(token, resource, { search, page_size: 50 })
        .then((data) => {
          if (!cancelled) {
            setOptions(data.results.map((item) => ({ id: item.id, label: item.label })));
          }
        })
        .catch((err) => {
          if (!cancelled) {
            setError(err instanceof Error ? err.message : 'Lookup failed.');
          }
        })
        .finally(() => {
          if (!cancelled) setIsLoading(false);
        });
    }, 180);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [disabled, resource, search, token]);

  if (!token || !resource || error) {
    return (
      <div className="relation-field">
        <input value={value} disabled={disabled} onChange={(event) => onChange(event.target.value)} placeholder="Record ID" />
        {error && <small className="field-warning">{error}</small>}
      </div>
    );
  }

  const hasSelectedOption = options.some((option) => option.id === value);

  return (
    <div className="relation-field">
      <input
        value={search}
        disabled={disabled}
        onChange={(event) => setSearch(event.target.value)}
        placeholder={`Search ${field.label.toLowerCase()}`}
      />
      <select value={value} disabled={disabled || isLoading} onChange={(event) => onChange(event.target.value)}>
        <option value="">Select {field.label}</option>
        {value && !hasSelectedOption && <option value={value}>Selected ID: {value}</option>}
        {options.map((option) => (
          <option key={option.id} value={option.id}>{option.label}</option>
        ))}
      </select>
      {isLoading && <small className="field-hint">Loading...</small>}
    </div>
  );
}

export function SchemaForm({
  fields,
  record,
  submitLabel,
  token,
  formId = 'schema-form',
  onSubmit,
}: {
  fields: FieldSchema[];
  record?: Record<string, unknown> | null;
  submitLabel: string;
  token?: string | null;
  formId?: string;
  onSubmit: (values: FormValues) => Promise<void> | void;
}) {
  const [values, setValues] = useState<FormValues>(() => initialValuesFromRecord(fields, record as never));
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setValues(initialValuesFromRecord(fields, record as never));
  }, [fields, record]);

  function setFieldValue(field: FieldSchema, value: string | boolean) {
    setValues((current) => ({ ...current, [field.name]: value }));
  }

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
      {fields.map((field) => {
        const mode = formModeForField(field);
        const fieldValue = values[field.name];
        const disabled = field.readonly || isSaving;

        return (
          <label key={field.name} className={`field-row field-row--${mode}`}>
            <span className="field-label">
              {field.label}{field.required ? ' *' : ''}
              <FieldMeta field={field} />
            </span>
            {mode === 'json-object' ? (
              <JsonObjectEditor
                value={fieldValue}
                disabled={disabled}
                resetKey={`${formId}:${field.name}`}
                onChange={(nextValue) => setFieldValue(field, nextValue)}
              />
            ) : mode === 'relation' ? (
              <RelationLookupField
                field={field}
                token={token}
                value={String(fieldValue ?? '')}
                disabled={disabled}
                onChange={(nextValue) => setFieldValue(field, nextValue)}
              />
            ) : mode === 'textarea' ? (
              <textarea
                value={String(fieldValue ?? '')}
                readOnly={field.readonly}
                disabled={isSaving}
                onChange={(event) => setFieldValue(field, event.target.value)}
                rows={3}
              />
            ) : mode === 'checkbox' ? (
              <input
                type="checkbox"
                checked={Boolean(fieldValue)}
                disabled={disabled}
                onChange={(event) => setFieldValue(field, event.target.checked)}
              />
            ) : mode === 'select' ? (
              <select
                value={String(fieldValue ?? '')}
                disabled={disabled}
                onChange={(event) => setFieldValue(field, event.target.value)}
              >
                <option value="">Select {field.label}</option>
                {field.choices.map((choice) => <option key={String(choice.value)} value={String(choice.value)}>{choice.label}</option>)}
              </select>
            ) : (
              <input
                type={inputTypeForField(field)}
                value={String(fieldValue ?? '')}
                readOnly={field.readonly}
                disabled={isSaving}
                onChange={(event) => setFieldValue(field, event.target.value)}
              />
            )}
          </label>
        );
      })}
      {error && <div className="form-error">{error}</div>}
      <button className="button button--primary" disabled={isSaving}>{isSaving ? 'Saving...' : submitLabel}</button>
    </form>
  );
}