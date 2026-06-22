import { useCallback, useEffect, useMemo, useState } from 'react';
import type { AdminRecord, AdminTableInfo, FieldSchema, RecordValue, TableRecords, TableSchema } from '../models/admin';
import { adminService } from '../services/adminService';

export interface FormValues {
  [field: string]: string | boolean;
}

export function parseFieldValue(field: FieldSchema, value: string | boolean): RecordValue {
  if (field.control === 'checkbox') {
    return Boolean(value);
  }
  if (typeof value !== 'string') {
    return value;
  }
  const trimmed = value.trim();
  if (!trimmed && !field.required) {
    return null;
  }
  if (field.type === 'integer') {
    return trimmed ? Number.parseInt(trimmed, 10) : null;
  }
  if (field.type === 'decimal') {
    return trimmed ? Number.parseFloat(trimmed) : null;
  }
  if (field.type === 'json') {
    return trimmed ? JSON.parse(trimmed) : null;
  }
  return trimmed;
}

export function buildSchemaPayload(fields: FieldSchema[], values: FormValues): AdminRecord {
  return fields.reduce<AdminRecord>((payload, field) => {
    if (field.readonly) return payload;
    if (!(field.name in values)) return payload;
    payload[field.name] = parseFieldValue(field, values[field.name]);
    return payload;
  }, {});
}

export function initialValuesFromRecord(fields: FieldSchema[], record?: AdminRecord | null): FormValues {
  return fields.reduce<FormValues>((values, field) => {
    const value = record?.[field.name] ?? field.default ?? '';
    values[field.name] = field.control === 'checkbox' ? Boolean(value) : typeof value === 'object' && value !== null ? JSON.stringify(value, null, 2) : String(value ?? '');
    return values;
  }, {});
}

export function useDataTableViewModel(token: string | null) {
  const [tables, setTables] = useState<AdminTableInfo[]>([]);
  const [selectedTable, setSelectedTable] = useState<string>('todos');
  const [schema, setSchema] = useState<TableSchema | null>(null);
  const [records, setRecords] = useState<TableRecords | null>(null);
  const [selectedRecord, setSelectedRecord] = useState<AdminRecord | null>(null);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedTableInfo = useMemo(
    () => tables.find((table) => table.table === selectedTable) ?? null,
    [tables, selectedTable],
  );

  const loadTables = useCallback(async () => {
    if (!token) return;
    const data = await adminService.tables(token);
    setTables(data.results);
    if (!data.results.some((item) => item.table === selectedTable) && data.results[0]) {
      setSelectedTable(data.results[0].table);
    }
  }, [selectedTable, token]);

  const loadRecords = useCallback(async () => {
    if (!token || !selectedTable) return;
    setIsLoading(true);
    setError(null);
    try {
      const [schemaData, recordData] = await Promise.all([
        adminService.tableSchema(token, selectedTable),
        adminService.listRecords(token, selectedTable, { page, page_size: 20, search }),
      ]);
      setSchema(schemaData);
      setRecords(recordData);
      setSelectedRecord(recordData.results[0] ?? null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load table.');
    } finally {
      setIsLoading(false);
    }
  }, [page, search, selectedTable, token]);

  useEffect(() => {
    void loadTables();
  }, [loadTables]);

  useEffect(() => {
    void loadRecords();
  }, [loadRecords]);

  async function createRecord(values: FormValues) {
    if (!token || !schema) return;
    await adminService.createRecord(token, selectedTable, buildSchemaPayload(schema.fields, values));
    await loadRecords();
  }

  async function updateRecord(id: string, values: FormValues) {
    if (!token || !schema) return;
    await adminService.updateRecord(token, selectedTable, id, buildSchemaPayload(schema.fields, values));
    await loadRecords();
  }

  async function deleteRecord(id: string) {
    if (!token) return;
    await adminService.deleteRecord(token, selectedTable, id);
    await loadRecords();
  }

  return {
    tables,
    selectedTable,
    selectedTableInfo,
    setSelectedTable: (table: string) => {
      setSelectedTable(table);
      setPage(1);
      setSelectedRecord(null);
    },
    schema,
    records,
    selectedRecord,
    setSelectedRecord,
    search,
    setSearch,
    page,
    setPage,
    isLoading,
    error,
    refresh: loadRecords,
    createRecord,
    updateRecord,
    deleteRecord,
  };
}