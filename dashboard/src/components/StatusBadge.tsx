export function StatusBadge({ value }: { value: string | number | boolean | null | undefined }) {
  const text = value === null || value === undefined || value === '' ? 'empty' : String(value);
  const normalized = text.toLowerCase();
  const tone = normalized.includes('critical') || normalized.includes('error') || normalized.includes('5xx') || normalized.includes('delete') || normalized.includes('rejected')
    ? 'danger'
    : normalized.includes('warning') || normalized.includes('pending') || normalized.includes('4xx')
      ? 'warning'
      : normalized.includes('success') || normalized.includes('active') || normalized.includes('2xx') || normalized.includes('approved') || normalized === 'true'
        ? 'success'
        : 'neutral';
  return <span className={`status-badge status-badge--${tone}`}>{text}</span>;
}