import type { ComponentProps } from 'react';

type IconName = 'overview' | 'data' | 'storage' | 'request' | 'runtime' | 'audit' | 'plus' | 'refresh' | 'search' | 'trash' | 'edit' | 'close' | 'shield';

const paths: Record<IconName, string> = {
  overview: 'M4 13h7V4H4v9Zm9 7h7V4h-7v16ZM4 20h7v-5H4v5Z',
  data: 'M4 6c0-1.1 3.6-2 8-2s8 .9 8 2-3.6 2-8 2-8-.9-8-2Zm0 5c0 1.1 3.6 2 8 2s8-.9 8-2M4 16c0 1.1 3.6 2 8 2s8-.9 8-2M4 6v10m16-10v10',
  storage: 'M5 6h14v12H5zM8 9h8M8 12h8M8 15h5',
  request: 'M6 4h12v16H6zM9 8h6M9 12h6M9 16h4',
  runtime: 'M4 17l5-5-5-5M11 19h9',
  audit: 'M12 3l7 3v5c0 4.4-2.8 8.4-7 10-4.2-1.6-7-5.6-7-10V6l7-3Zm-3 9 2 2 4-5',
  plus: 'M12 5v14M5 12h14',
  refresh: 'M20 7v5h-5M4 17v-5h5M18 9a6 6 0 0 0-10-3M6 15a6 6 0 0 0 10 3',
  search: 'M10.5 18a7.5 7.5 0 1 1 5.3-12.8 7.5 7.5 0 0 1-5.3 12.8ZM16 16l4 4',
  trash: 'M5 7h14M10 11v6M14 11v6M7 7l1 13h8l1-13M9 7V4h6v3',
  edit: 'M4 20h4l10-10-4-4L4 16v4ZM13 7l4 4',
  close: 'M6 6l12 12M18 6 6 18',
  shield: 'M12 3l7 3v5c0 4.4-2.8 8.4-7 10-4.2-1.6-7-5.6-7-10V6l7-3Z',
};

export function Icon({ name, ...props }: { name: IconName } & ComponentProps<'svg'>) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d={paths[name]} />
    </svg>
  );
}