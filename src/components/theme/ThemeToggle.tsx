import type { Theme } from './useTheme';

type ThemeToggleProps = {
  theme: Theme;
  onToggle: () => void;
};

export function ThemeToggle({ theme, onToggle }: ThemeToggleProps) {
  const nextTheme = theme === 'dark' ? 'light' : 'dark';

  return (
    <button
      type="button"
      onClick={onToggle}
      className={[
        'relative inline-flex h-7 w-14 items-center rounded-full border p-0.5 transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-slate-950',
        theme === 'dark'
          ? 'border-slate-700 bg-slate-800'
          : 'border-slate-300 bg-slate-200',
      ].join(' ')}
      aria-label={`Switch to ${nextTheme} theme`}
      title={`Switch to ${nextTheme} theme`}
    >
      <span
        className={[
          'flex h-6 w-6 items-center justify-center rounded-full bg-white text-xs shadow-sm transition-transform',
          theme === 'dark'
            ? 'translate-x-7 text-slate-950'
            : 'translate-x-0 text-amber-500',
        ].join(' ')}
        aria-hidden="true"
      >
        {theme === 'dark' ? '☾' : '☀'}
      </span>
    </button>
  );
}
