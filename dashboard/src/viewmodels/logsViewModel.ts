import { useCallback, useEffect, useState } from 'react';
import type { RequestLogPage, RuntimeLogData } from '../models/logs';
import { adminService } from '../services/adminService';

export function useRequestLogsViewModel(token: string | null) {
  const [logs, setLogs] = useState<RequestLogPage | null>(null);
  const [search, setSearch] = useState('');
  const [statusClass, setStatusClass] = useState('');
  const [method, setMethod] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    setError(null);
    try {
      setLogs(await adminService.requestLogs(token, { page: 1, page_size: 50, search, status_class: statusClass, method }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load request logs.');
    } finally {
      setIsLoading(false);
    }
  }, [method, search, statusClass, token]);

  useEffect(() => {
    void load();
  }, [load]);

  return { logs, search, setSearch, statusClass, setStatusClass, method, setMethod, isLoading, error, refresh: load };
}

export function useRuntimeLogsViewModel(token: string | null) {
  const [stream, setStream] = useState('runtime');
  const [data, setData] = useState<RuntimeLogData | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    setError(null);
    try {
      setData(await adminService.runtimeLogs(token, stream, 200));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load runtime logs.');
    } finally {
      setIsLoading(false);
    }
  }, [stream, token]);

  useEffect(() => {
    void load();
  }, [load]);

  return { stream, setStream, data, isLoading, error, refresh: load };
}