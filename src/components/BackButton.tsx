import { useNavigate } from 'react-router-dom';

type BackButtonProps = {
  label?: string;
  className?: string;
};

export function BackButton({ label = 'Back', className = '' }: BackButtonProps) {
  const navigate = useNavigate();

  return (
    <button
      className={`group inline-flex items-center gap-1 rounded-md py-1 text-sm font-medium text-brand-600 transition-colors duration-200 hover:text-brand-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 motion-reduce:transition-none dark:text-brand-400 dark:hover:text-brand-300 dark:focus-visible:ring-offset-slate-950 ${className}`}
      onClick={() => navigate(-1)}
      type="button"
    >
      <svg
        aria-hidden="true"
        className="h-4 w-4 transition-transform duration-200 group-hover:-translate-x-1 motion-reduce:transition-none"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        viewBox="0 0 24 24"
      >
        <path d="M19 12H5M12 19l-7-7 7-7" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      {label}
    </button>
  );
}
