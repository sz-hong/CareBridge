import type {
  ActivityData,
  AdminRecord,
  AdminTableIndex,
  OverviewData,
  PresignedFile,
  RecordDetail,
  StorageObjectInfo,
  TableRecords,
  TableSchema,
} from '../models/admin';
import type { PageResult } from '../models/api';
import type { AuditLogPage, RequestLogPage, RuntimeLogData } from '../models/logs';
import { apiRequest, toQuery, type QueryParams } from './apiClient';

export interface ListParams extends QueryParams {
  page?: number;
  page_size?: number;
  search?: string;
  date_from?: string;
  date_to?: string;
}

export const adminService = {
  overview(token: string): Promise<OverviewData> {
    return apiRequest('/admin/overview/', { token });
  },

  activity(token: string, limit = 20): Promise<ActivityData> {
    return apiRequest(`/admin/activity/${toQuery({ limit })}`, { token });
  },

  tables(token: string): Promise<AdminTableIndex> {
    return apiRequest('/admin/tables/', { token });
  },

  tableSchema(token: string, table: string): Promise<TableSchema> {
    return apiRequest(`/admin/tables/${table}/schema/`, { token });
  },

  listRecords(token: string, table: string, params: ListParams = {}): Promise<TableRecords> {
    return apiRequest(`/admin/tables/${table}/${toQuery(params)}`, { token });
  },

  createRecord(token: string, table: string, body: AdminRecord): Promise<RecordDetail> {
    return apiRequest(`/admin/tables/${table}/`, {
      method: 'POST',
      token,
      body: JSON.stringify(body),
    });
  },

  recordDetail(token: string, table: string, id: string): Promise<RecordDetail> {
    return apiRequest(`/admin/records/${table}/${id}/`, { token });
  },

  updateRecord(token: string, table: string, id: string, body: AdminRecord): Promise<RecordDetail> {
    return apiRequest(`/admin/records/${table}/${id}/`, {
      method: 'PATCH',
      token,
      body: JSON.stringify(body),
    });
  },

  deleteRecord(token: string, table: string, id: string): Promise<{ deleted: boolean; delete_mode: string }> {
    return apiRequest(`/admin/records/${table}/${id}/`, { method: 'DELETE', token });
  },

  requestLogs(token: string, params: ListParams & { method?: string; status_class?: string; path?: string } = {}): Promise<RequestLogPage> {
    return apiRequest(`/admin/request-logs/${toQuery(params)}`, { token });
  },

  auditLogs(token: string, params: ListParams & { action?: string; table?: string; record_id?: string } = {}): Promise<AuditLogPage> {
    return apiRequest(`/admin/audit-logs/${toQuery(params)}`, { token });
  },

  runtimeLogs(token: string, stream = 'runtime', lines = 100): Promise<RuntimeLogData> {
    return apiRequest(`/admin/logs/${toQuery({ stream, lines })}`, { token });
  },

  storageObjects(token: string, params: ListParams & { prefix?: string; orphan?: boolean } = {}): Promise<PageResult<StorageObjectInfo>> {
    return apiRequest(`/admin/storage/objects/${toQuery(params)}`, { token });
  },

  presign(token: string, bucket: string, object_key: string, mode: 'preview' | 'download'): Promise<PresignedFile> {
    return apiRequest(`/admin/files/presign/${toQuery({ bucket, object_key, mode })}`, { token });
  },
};