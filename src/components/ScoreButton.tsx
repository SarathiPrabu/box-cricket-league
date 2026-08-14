import type { ButtonHTMLAttributes, ReactNode } from 'react';

type ScoreButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode;
  tone?: 'default' | 'accent' | 'danger';
};

const toneClasses = {
  default: 'border-slate-300 bg-white text-slate-900 hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-900 dark:text-white dark:hover:bg-slate-800',
  accent: 'border-brand-500 bg-brand-500 text-slate-950 hover:bg-brand-400',
  danger: 'border-red-300 bg-red-50 text-red-700 hover:bg-red-100 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300 dark:hover:bg-red-950/70',
};

export function ScoreButton({ children, className = '', tone = 'default', ...props }: ScoreButtonProps) {
  return (
    <button
      {...props}
      className={`min-h-11 rounded-lg border px-4 py-2 text-sm font-bold transition disabled:cursor-not-allowed disabled:opacity-50 ${toneClasses[tone]} ${className}`}
      type={props.type ?? 'button'}
    >
      {children}
    </button>
  );
}
