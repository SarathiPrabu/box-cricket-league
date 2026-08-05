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
        'inline-flex h-10 w-10 items-center justify-center rounded-full border text-lg transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-slate-950',
        theme === 'dark'
          ? 'border-slate-700 bg-slate-900 text-slate-100 hover:bg-slate-800'
          : 'border-slate-300 bg-slate-100 text-amber-500 hover:bg-slate-200',
      ].join(' ')}
      aria-label={`Switch to ${nextTheme} theme`}
      title={`Switch to ${nextTheme} theme`}
    >
      <span
        className="flex items-center justify-center leading-none"
        aria-hidden="true"
      >
        {theme === 'dark' ? '☾' : '☀'}
      </span>
    </button>
  );
}
