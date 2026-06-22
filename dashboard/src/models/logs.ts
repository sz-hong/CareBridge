import type { PageResult } from './api';

export interface RequestLog {
  id: string;
  request_id: string | null;
  method: string;
  path: string;
  query: string;
  status_code: number;
  status_class: string | null;
  success: boolean;
  duration_ms: number;
  user_id: string | null;
  user_email: string | null;
  is_staff: boolean;
  ip: string | null;
  user_agent: string;
  error_code: string | null;
  error_message: string | null;
  created_at: string;
}

export interface AuditLog {
  id: string;
  request_id: string | null;
  actor_id: string | null;
  actor_email: string | null;
  action: string;
  table: string | null;
  record_id: string | null;
  bucket: string | null;
  object_key: string | null;
  status_code: number;
  metadata: Record<string, unknown>;
  created_at: string;
}

export interface RuntimeLogLine {
  timestamp: string | null;
  level: string;
  message: string;
  request_id: string | null;
}

export interface RuntimeLogData {
  stream: string;
  lines: RuntimeLogLine[];
  next_cursor: string | null;
}

export type RequestLogPage = PageResult<RequestLog>;
export type AuditLogPage = PageResult<AuditLog>;