import { NavLink, Outlet } from 'react-router-dom';
import { ThemeToggle } from '../components/theme/ThemeToggle';
import { useTheme } from '../components/theme/useTheme';
import { GoogleSignInButton } from '../features/auth/GoogleSignInButton';
import { useAuth } from '../features/auth/authState';

const navItems = [
  { to: '/', label: 'Home' },
  { to: '/players', label: 'Players' },
  { to: '/teams', label: 'Teams' },
  { to: '/matches', label: 'Matches' },
  { to: '/standings', label: 'Standings' },
  { to: '/leaderboards', label: 'Leaderboards' },
];

const roleLabels = {
  admin: 'Admin',
  scorer: 'Scorer',
  player: 'Player',
  team_manager: 'Team Manager',
};

export function AppLayout() {
  const { theme, toggleTheme } = useTheme();
  const { user, isSignedIn, isLoading, authError, signOut } = useAuth();
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
            <div className="flex items-center gap-3">
              {isLoading ? (
                <span className="rounded-md bg-slate-100 px-3 py-2 text-sm font-medium text-slate-600 dark:bg-slate-900 dark:text-slate-300">
                  Checking login...
                </span>
              ) : isSignedIn ? (
                <>
                  <div className="flex flex-col items-start gap-1 sm:items-end">
                    <span className="rounded-full bg-emerald-100 px-3 py-2 text-sm font-medium text-emerald-800 dark:bg-emerald-950 dark:text-emerald-200">
                      Hi {user?.name}
                    </span>
                    {user?.roles.length ? (
                      <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
                        {user.roles
                          .map((role) => roleLabels[role.role])
                          .join(', ')}
                      </span>
                    ) : null}
                  </div>
                  <button
                    type="button"
                    onClick={signOut}
                    className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
                  >
                    Sign out
                  </button>
                </>
              ) : (
                <GoogleSignInButton />
              )}
            </div>
            {authError ? (
              <p className="max-w-sm text-sm text-red-600 dark:text-red-400">
                {authError}
              </p>
            ) : null}
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
