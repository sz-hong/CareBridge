import { describe, expect, it } from 'vitest';
import type { FieldSchema } from '../models/admin';
import { formModeForField, jsonRowsFromValue, jsonRowsToFormValue } from '../components/schemaFormHelpers';

const baseField = {
  label: 'Field',
  required: false,
  readonly: false,
  default: null,
  choices: [],
} satisfies Partial<FieldSchema>;

describe('schema form helpers', () => {
  it('renders relation fields as lookup controls instead of raw ids', () => {
    const field = {
      ...baseField,
      name: 'family_id',
      type: 'relation',
      control: 'relation',
      relation: { resource: 'families', lookup_url: '/api/v1/admin/lookups/families/' },
    } as FieldSchema;

    expect(formModeForField(field)).toBe('relation');
  });

  it('converts json object rows into the form value expected by the payload builder', () => {
    const rows = jsonRowsFromValue('{"source":"dashboard","active":true,"count":2}');

    expect(rows).toEqual([
      { key: 'source', value: 'dashboard' },
      { key: 'active', value: 'true' },
      { key: 'count', value: '2' },
    ]);

    const formValue = jsonRowsToFormValue([
      { key: 'note', value: 'Follow up' },
      { key: 'active', value: 'true' },
      { key: 'count', value: '2' },
      { key: '', value: 'ignored' },
    ]);

    expect(JSON.parse(formValue)).toEqual({
      note: 'Follow up',
      active: true,
      count: 2,
    });
  });
});