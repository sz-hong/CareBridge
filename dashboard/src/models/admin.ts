import type { PageResult } from './api';

export type RecordValue = string | number | boolean | null | Record<string, unknown> | unknown[];
export type AdminRecord = Record<string, RecordValue>;

export interface TableCapability {
  list: boolean;
  detail: boolean;
  schema: boolean;
  create: boolean;
  update: boolean;
  delete: boolean;
}

export interface AdminTableInfo {
  table: string;
  display_name: string;
  category: string;
  model: string;
  capabilities: TableCapability;
  endpoints: {
    list: string;
    schema: string;
    detail: string;
  };
}

export interface AdminTableIndex {
  results: AdminTableInfo[];
  count: number;
}

export interface FieldChoice {
  value: string | number | boolean | null;
  label: string;
}

export interface RelationConfig {
  resource: 'users' | 'families' | string;
  lookup_url: string;
}

export interface FieldSchema {
  name: string;
  label: string;
  type: 'string' | 'integer' | 'decimal' | 'boolean' | 'date' | 'datetime' | 'json' | 'choice' | 'relation';
  control: 'text' | 'textarea' | 'email' | 'url' | 'number' | 'checkbox' | 'date' | 'datetime' | 'json' | 'select' | 'relation' | 'uuid';
  required: boolean;
  readonly: boolean;
  default: RecordValue;
  choices: FieldChoice[];
  relation?: RelationConfig;
}

export interface TableSchema {
  table: string;
  create_allowed: boolean;
  delete_allowed: boolean;
  fields: FieldSchema[];
}

export interface RecordDetail {
  record: AdminRecord;
  related_files?: StorageObjectInfo[];
  raw: AdminRecord;
}

export interface TableRecords extends PageResult<AdminRecord> {}

export interface OverviewData {
  kpis: Array<{ label: string; value: number; delta_24h: number }>;
  tables: Array<{ table: string; count: number; created_24h: number; updated_24h: number }>;
  alerts: Array<{ severity: string; title: string; count: number }>;
}

export interface ActivityItem {
  id: string;
  table: string;
  record_id: string;
  action: string;
  actor: string | null;
  created_at: string | null;
}

export interface ActivityData {
  results: ActivityItem[];
  next_cursor: string | null;
}

export interface StorageObjectInfo {
  bucket: string;
  object_key: string;
  size: number | null;
  last_modified: string | null;
  content_type: string | null;
  linked_table: string | null;
  linked_record_id: string | null;
  orphan: boolean;
  filename: string | null;
  previewable: boolean;
}

export interface PresignedFile {
  url: string;
  expires_in: number;
  content_type: string | null;
  filename: string | null;
  size: number | null;
  disposition: string;
}