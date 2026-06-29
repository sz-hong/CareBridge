import type { FieldSchema, RecordValue } from '../models/admin';

export type FormFieldMode = 'text' | 'textarea' | 'checkbox' | 'select' | 'relation' | 'json-object';

export interface JsonEditorRow {
  key: string;
  value: string;
}

export function formModeForField(field: FieldSchema): FormFieldMode {
  if (field.control === 'relation') return 'relation';
  if (field.control === 'json') return 'json-object';
  if (field.control === 'textarea') return 'textarea';
  if (field.control === 'checkbox') return 'checkbox';
  if (field.control === 'select') return 'select';
  return 'text';
}

function parseJsonValue(value: RecordValue | string | boolean | undefined): unknown {
  if (value === undefined || value === null || value === '') return {};
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch {
      return {};
    }
  }
  return value;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringifyRowValue(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return JSON.stringify(value);
}

export function jsonRowsFromValue(value: RecordValue | string | boolean | undefined): JsonEditorRow[] {
  const parsed = parseJsonValue(value);
  if (!isPlainObject(parsed) || Object.keys(parsed).length === 0) {
    return [{ key: '', value: '' }];
  }
  return Object.entries(parsed).map(([key, rowValue]) => ({
    key,
    value: stringifyRowValue(rowValue),
  }));
}

function parseRowValue(value: string): unknown {
  const trimmed = value.trim();
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (trimmed === 'null') return null;
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);
  if ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return value;
    }
  }
  return value;
}

export function jsonRowsToFormValue(rows: JsonEditorRow[]): string {
  const payload = rows.reduce<Record<string, unknown>>((result, row) => {
    const key = row.key.trim();
    if (!key) return result;
    result[key] = parseRowValue(row.value);
    return result;
  }, {});
  return JSON.stringify(payload);
}

export function inputTypeForField(field: FieldSchema): string {
  if (field.control === 'number') return 'number';
  if (field.control === 'datetime') return 'datetime-local';
  if (field.control === 'date') return 'date';
  if (field.control === 'email') return 'email';
  if (field.control === 'url') return 'url';
  return 'text';
}