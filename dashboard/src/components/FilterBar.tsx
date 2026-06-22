import type { ReactNode } from 'react';
import { Icon } from './Icon';

export function FilterBar({
  search,
  onSearchChange,
  onRefresh,
  children,
}: {
  search?: string;
  onSearchChange?: (value: string) => void;
  onRefresh?: () => void;
  children?: ReactNode;
}) {
  return (
    <div className="filter-bar">
      {onSearchChange && (
        <label className="search-box">
          <Icon name="search" />
          <input value={search ?? ''} onChange={(event) => onSearchChange(event.target.value)} placeholder="Search" />
        </label>
      )}
      <div className="filter-bar__controls">{children}</div>
      {onRefresh && <button className="icon-button" onClick={onRefresh} title="Refresh"><Icon name="refresh" /></button>}
    </div>
  );
}