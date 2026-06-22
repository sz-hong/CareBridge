export interface ApiEnvelope<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    fields?: Record<string, string[]>;
  };
}

export class ApiRequestError extends Error {
  code: string;
  status: number;
  fields?: Record<string, string[]>;

  constructor(message: string, code: string, status: number, fields?: Record<string, string[]>) {
    super(message);
    this.name = 'ApiRequestError';
    this.code = code;
    this.status = status;
    this.fields = fields;
  }
}

export interface PageResult<T> {
  results: T[];
  count: number;
  next: number | null;
  previous: number | null;
  page: number;
  page_size: number;
}