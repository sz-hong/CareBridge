import { useCallback, useEffect, useState } from 'react';
import type { AuditLogPage } from '../models/logs';
import { adminService } from '../services/adminService';

export function useAuditViewModel(token: string | null) {
  const [logs, setLogs] = useState<AuditLogPage | null>(null);
  const [table, setTable] = useState('');
  const [action, setAction] = useState('');
  const [search, setSearch] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    setError(null);
    try {
      setLogs(await adminService.auditLogs(token, { page: 1, page_size: 50, table, action, search }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load audit logs.');
    } finally {
      setIsLoading(false);
    }
  }, [action, search, table, token]);

  useEffect(() => {
    void load();
  }, [load]);

  return { logs, table, setTable, action, setAction, search, setSearch, isLoading, error, refresh: load };
}