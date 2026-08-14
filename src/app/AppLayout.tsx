import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import logo from '../assets/logo.png';
import { MobileMenu } from '../components/MobileMenu';
import { ThemeToggle } from '../components/theme/ThemeToggle';
import { useTheme } from '../components/theme/useTheme';
import { GoogleSignInButton } from '../features/auth/GoogleSignInButton';
import { useAuth, type AuthUser, type LeagueRoleName } from '../features/auth/authState';
import { canAccessRoute, type ProtectedRouteName } from './routeAccess';

const navItems = [
  { to: '/', label: 'Home' },
  { to: '/admin/roles', label: 'Roles', access: 'adminRoles' as const },
  { to: '/admin/team-managers', label: 'Team managers', access: 'teamManagers' as const },
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

function RoleSelector({
  user,
  onChange,
}: {
  user: AuthUser;
  onChange: (role: LeagueRoleName | null) => void;
}) {
  if (user.roles.length < 2) {
    return user.activeRole ? (
      <span className="block truncate text-xs font-medium text-slate-500 dark:text-slate-400">
        {roleLabels[user.activeRole]}
      </span>
    ) : null;
  }

  return (
    <label className="flex items-center gap-1 text-xs font-medium text-slate-500 dark:text-slate-400">
      <span className="sr-only">View as role</span>
      <select
        aria-label="View as role"
        value={user.activeRole ?? ''}
        onChange={(event) => {
          onChange((event.target.value || null) as LeagueRoleName | null);
        }}
        className="form-select w-auto max-w-32 px-2 font-semibold"
      >
        <option value="">User</option>
        {user.roles.map((role) => (
          <option key={`${role.leagueId}-${role.role}`} value={role.role}>
            {roleLabels[role.role]}
          </option>
        ))}
      </select>
    </label>
  );
}

export function AppLayout() {
  const navigate = useNavigate();
  const { theme, toggleTheme } = useTheme();
  const { user, isSignedIn, isLoading, authError, signOut, setActiveRole } = useAuth();
  const visibleNavItems = navItems.filter(
    (item) => !item.access || canAccessRoute(user, item.access as ProtectedRouteName),
  );
  const appThemeClass =
    theme === 'dark'
      ? 'dark min-h-screen bg-slate-950 text-slate-100'
      : 'min-h-screen bg-slate-50 text-slate-950';

  return (
    <div className={appThemeClass}>
      <header className="relative border-b border-slate-200 bg-white/95 dark:border-slate-800 dark:bg-slate-950/95">
        <div className="mx-auto max-w-6xl px-4 lg:hidden">
          <div className="flex min-h-16 items-center justify-between gap-3">
            <NavLink to="/" className="flex min-w-0 items-center gap-2.5" aria-label="Box Cricket League home">
              <img src={logo} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
              <span className="truncate text-sm font-bold uppercase tracking-wide text-brand-600 dark:text-brand-400">
                Box Cricket League
              </span>
            </NavLink>
            <MobileMenu items={visibleNavItems}>
              <div className="flex flex-wrap items-center gap-2">
                <ThemeToggle theme={theme} onToggle={toggleTheme} />
                {isLoading ? (
                  <span className="min-h-11 rounded-lg bg-slate-100 px-3 py-2 text-sm font-medium text-slate-600 dark:bg-slate-900 dark:text-slate-300">Checking login...</span>
                ) : isSignedIn ? (
                  <>
                    <span className="max-w-full truncate rounded-lg bg-slate-900 px-3 py-2 text-sm font-medium text-emerald-300 dark:bg-slate-800 dark:text-emerald-200">Hi {user?.name}</span>
                    {user ? <RoleSelector user={user} onChange={setActiveRole} /> : null}
                    <button type="button" onClick={() => { void signOut().then(() => navigate('/')); }} className="min-h-11 rounded-lg bg-slate-900 px-3 py-2 text-sm font-medium text-slate-200 transition hover:bg-slate-800 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700">Sign out</button>
                  </>
                ) : <GoogleSignInButton />}
              </div>
              {authError ? <p className="mt-3 text-sm text-red-600 dark:text-red-400">{authError}</p> : null}
            </MobileMenu>
          </div>
        </div>
        <div className="mx-auto hidden min-h-16 max-w-6xl items-center gap-5 px-4 lg:flex">
          <NavLink to="/" className="flex shrink-0 items-center gap-2.5" aria-label="Box Cricket League home">
            <img src={logo} alt="" className="h-10 w-10 rounded-full object-cover" />
            <span className="text-sm font-bold uppercase tracking-wide text-brand-600 dark:text-brand-400">Box Cricket League</span>
          </NavLink>
          <nav className="flex min-w-0 flex-1 items-center justify-center gap-1" aria-label="Main navigation">
            {visibleNavItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                className={({ isActive }) => [
                  'shrink-0 rounded-lg px-2.5 py-2 text-sm font-semibold transition',
                  isActive ? 'bg-brand-500 text-slate-950 shadow-sm' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-950 dark:text-slate-300 dark:hover:bg-slate-900 dark:hover:text-white',
                ].join(' ')}
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex shrink-0 items-center gap-2">
            <ThemeToggle theme={theme} onToggle={toggleTheme} />
            {isLoading ? (
              <span className="rounded-lg bg-slate-100 px-3 py-2 text-sm font-medium text-slate-600 dark:bg-slate-900 dark:text-slate-300">
                Checking login...
              </span>
            ) : isSignedIn ? (
              <>
                <div className="min-w-0 max-w-36">
                  <span className="block truncate text-sm font-semibold text-slate-700 dark:text-slate-200">{user?.name}</span>
                  {user ? <RoleSelector user={user} onChange={setActiveRole} /> : null}
                </div>
                <button
                  type="button"
                  onClick={() => {
                    void signOut().then(() => navigate('/'));
                  }}
                  className="rounded-lg px-2.5 py-2 text-sm font-semibold text-slate-600 transition hover:bg-slate-100 hover:text-slate-950 dark:text-slate-300 dark:hover:bg-slate-900 dark:hover:text-white"
                >
                  Sign out
                </button>
              </>
            ) : (
              <GoogleSignInButton />
            )}
          </div>
          {authError ? (
            <p className="absolute right-4 top-full z-10 mt-2 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 shadow-sm dark:bg-red-950 dark:text-red-200" role="alert">{authError}</p>
          ) : null}
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6 sm:py-8">
        <Outlet />
      </main>
    </div>
  );
}
