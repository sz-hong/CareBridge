import { useCallback, useEffect, useState } from 'react';
import type { ActivityData, AdminTableInfo, OverviewData } from '../models/admin';
import { adminService } from '../services/adminService';

export function useOverviewViewModel(token: string | null) {
  const [overview, setOverview] = useState<OverviewData | null>(null);
  const [tables, setTables] = useState<AdminTableInfo[]>([]);
  const [activity, setActivity] = useState<ActivityData | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    setError(null);
    try {
      const [overviewData, tableData, activityData] = await Promise.all([
        adminService.overview(token),
        adminService.tables(token),
        adminService.activity(token, 16),
      ]);
      setOverview(overviewData);
      setTables(tableData.results);
      setActivity(activityData);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load overview.');
    } finally {
      setIsLoading(false);
    }
  }, [token]);

  useEffect(() => {
    void load();
  }, [load]);

  return { overview, tables, activity, isLoading, error, refresh: load };
}