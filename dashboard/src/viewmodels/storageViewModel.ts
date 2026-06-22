import { useCallback, useEffect, useState } from 'react';
import type { PageResult } from '../models/api';
import type { StorageObjectInfo } from '../models/admin';
import { adminService } from '../services/adminService';

export function useStorageViewModel(token: string | null) {
  const [objects, setObjects] = useState<PageResult<StorageObjectInfo> | null>(null);
  const [prefix, setPrefix] = useState('');
  const [orphanOnly, setOrphanOnly] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    setError(null);
    try {
      setObjects(await adminService.storageObjects(token, { page: 1, page_size: 50, prefix, orphan: orphanOnly ? true : undefined }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load storage objects.');
    } finally {
      setIsLoading(false);
    }
  }, [orphanOnly, prefix, token]);

  useEffect(() => {
    void load();
  }, [load]);

  async function preview(object: StorageObjectInfo) {
    if (!token) return;
    const presigned = await adminService.presign(token, object.bucket, object.object_key, object.previewable ? 'preview' : 'download');
    window.open(presigned.url, '_blank', 'noopener,noreferrer');
  }

  return { objects, prefix, setPrefix, orphanOnly, setOrphanOnly, isLoading, error, refresh: load, preview };
}