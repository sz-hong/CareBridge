import { describe, expect, it } from 'vitest';
import type { FieldSchema } from '../models/admin';
import { buildSchemaPayload } from '../viewmodels/dataTableViewModel';

const baseField = {
  label: 'Field',
  required: false,
  readonly: false,
  default: null,
  choices: [],
} satisfies Partial<FieldSchema>;

describe('buildSchemaPayload', () => {
  it('parses schema fields and ignores readonly values', () => {
    const fields: FieldSchema[] = [
      { ...baseField, name: 'title', type: 'string', control: 'text' } as FieldSchema,
      { ...baseField, name: 'amount', type: 'decimal', control: 'number' } as FieldSchema,
      { ...baseField, name: 'count', type: 'integer', control: 'number' } as FieldSchema,
      { ...baseField, name: 'metadata', type: 'json', control: 'json' } as FieldSchema,
      { ...baseField, name: 'readonly', type: 'string', control: 'text', readonly: true } as FieldSchema,
    ];

    const payload = buildSchemaPayload(fields, {
      title: ' Follow up ',
      amount: '12.5',
      count: '3',
      metadata: '{"source":"dashboard"}',
      readonly: 'skip',
    });

    expect(payload).toEqual({
      title: 'Follow up',
      amount: 12.5,
      count: 3,
      metadata: { source: 'dashboard' },
    });
  });
});