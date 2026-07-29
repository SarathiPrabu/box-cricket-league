import { NavLink, Outlet } from 'react-router-dom';
import { ThemeToggle } from '../components/theme/ThemeToggle';
import { useTheme } from '../components/theme/useTheme';

const navItems = [
  { to: '/', label: 'Home' },
  { to: '/players', label: 'Players' },
  { to: '/teams', label: 'Teams' },
  { to: '/matches', label: 'Matches' },
  { to: '/leaderboards', label: 'Leaderboards' },
];

export function AppLayout() {
  const { theme, toggleTheme } = useTheme();
  const appThemeClass =
    theme === 'dark'
      ? 'dark min-h-screen bg-slate-950 text-slate-100'
      : 'min-h-screen bg-slate-50 text-slate-950';

  return (
    <div className={appThemeClass}>
      <header className="border-b border-slate-200 bg-white/95 dark:border-slate-800 dark:bg-slate-950/95">
        <div className="mx-auto flex max-w-5xl flex-col gap-4 px-4 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-medium uppercase tracking-wide text-brand-600 dark:text-brand-400">
              Box Cricket League
            </p>
            <h1 className="text-xl font-semibold text-slate-950 dark:text-white">
              MVP Foundation
            </h1>
          </div>
          <div className="flex flex-col gap-3 sm:items-end">
            <ThemeToggle theme={theme} onToggle={toggleTheme} />
            <nav className="flex flex-wrap gap-2">
              {navItems.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.to === '/'}
                  className={({ isActive }) =>
                    [
                      'rounded-md px-3 py-2 text-sm font-medium transition',
                      isActive
                        ? 'bg-brand-500 text-slate-950'
                        : 'bg-white text-slate-700 hover:bg-slate-100 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800 dark:hover:text-white',
                    ].join(' ')
                  }
                >
                  {item.label}
                </NavLink>
              ))}
            </nav>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-5xl px-4 py-8">
        <Outlet />
      </main>
    </div>
  );
}
