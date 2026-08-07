import { useEffect, useState, type ReactNode } from 'react';
import { NavLink } from 'react-router-dom';

export type MobileMenuItem = {
  to: string;
  label: string;
};

type MobileMenuProps = {
  items: MobileMenuItem[];
  children: ReactNode;
};

export function MobileMenu({ items, children }: MobileMenuProps) {
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    if (!isOpen) return;

    const previousOverflow = document.body.style.overflow;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setIsOpen(false);
    };

    document.body.style.overflow = 'hidden';
    document.addEventListener('keydown', closeOnEscape);

    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [isOpen]);

  return (
    <div className="lg:hidden">
      <button
        aria-controls="mobile-navigation"
        aria-expanded={isOpen}
        aria-label={isOpen ? 'Close navigation menu' : 'Open navigation menu'}
        className="inline-flex h-11 w-11 items-center justify-center rounded-lg border border-slate-300 bg-white p-2 text-slate-700 transition hover:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-brand-500/50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
        onClick={() => setIsOpen((open) => !open)}
        type="button"
      >
        <span aria-hidden="true" className="flex w-5 flex-col gap-1">
          <span
            className={`block h-0.5 w-5 origin-center rounded-full bg-current transition-transform duration-200 ease-out ${isOpen ? 'translate-y-1.5 rotate-45' : ''}`}
          />
          <span
            className={`block h-0.5 w-5 rounded-full bg-current transition-opacity duration-150 ease-out ${isOpen ? 'opacity-0' : 'opacity-100'}`}
          />
          <span
            className={`block h-0.5 w-5 origin-center rounded-full bg-current transition-transform duration-200 ease-out ${isOpen ? '-translate-y-1.5 -rotate-45' : ''}`}
          />
        </span>
      </button>

      <div
        aria-hidden={!isOpen}
        className={`fixed inset-0 z-40 bg-slate-950/50 backdrop-blur-[2px] transition-opacity duration-300 motion-reduce:transition-none ${isOpen ? 'pointer-events-auto opacity-100' : 'pointer-events-none opacity-0'}`}
        onClick={() => setIsOpen(false)}
      />
      <aside
        aria-hidden={!isOpen}
        aria-label="Mobile navigation"
        aria-modal="true"
        className={`fixed inset-y-0 right-0 z-50 flex w-[min(22rem,calc(100vw-1.25rem))] flex-col border-l border-slate-200 bg-white p-5 shadow-2xl transition-transform duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none dark:border-slate-800 dark:bg-slate-950 ${isOpen ? 'pointer-events-auto translate-x-0' : 'pointer-events-none translate-x-full'}`}
        id="mobile-navigation"
        role="dialog"
      >
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-brand-600 dark:text-brand-400">Box Cricket League</p>
            <h2 className="mt-1 text-2xl font-bold tracking-tight text-slate-950 dark:text-white">Explore the league</h2>
          </div>
          <button
            aria-label="Close navigation menu"
            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-slate-50 text-xl text-slate-700 transition hover:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-brand-500/50 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
            onClick={() => setIsOpen(false)}
            type="button"
          >
            <span aria-hidden="true">×</span>
          </button>
        </div>

        <nav className="mt-8 grid gap-1.5">
          {items.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              onClick={() => setIsOpen(false)}
              className={({ isActive }) => [
                'group flex min-h-12 items-center rounded-xl border px-4 py-2 text-base font-semibold transition focus:outline-none focus:ring-2 focus:ring-brand-500/50',
                isActive
                  ? 'border-brand-500 bg-brand-500 text-slate-950 shadow-sm'
                  : 'border-transparent bg-slate-50/80 text-slate-700 hover:border-slate-200 hover:bg-white hover:shadow-sm dark:bg-slate-900/60 dark:text-slate-300 dark:hover:border-slate-700 dark:hover:bg-slate-900 dark:hover:text-white',
              ].join(' ')}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>

        <div className="mt-auto border-t border-slate-200 pt-5 dark:border-slate-800">
          <div className="rounded-2xl bg-slate-50 p-3 dark:bg-slate-900">{children}</div>
        </div>
      </aside>
    </div>
  );
}
