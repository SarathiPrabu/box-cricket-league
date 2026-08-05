import { useEffect, useState } from 'react';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';
import type { LeagueRoleName } from '../auth/authState';

const leagueSlug = 'box-cricket-league';

const roleOptions = [
  { value: '', label: 'No role' },
  { value: 'admin', label: 'Admin' },
  { value: 'scorer', label: 'Scorer' },
  { value: 'player', label: 'Player' },
  { value: 'team_manager', label: 'Team Manager' },
] satisfies { value: LeagueRoleName | ''; label: string }[];

type RoleAssignment = {
  user_id: string;
  email: string | null;
  display_name: string | null;
  role: LeagueRoleName | null;
};

type RoleAssignmentState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; users: RoleAssignment[] };

export function RoleAssignmentPage() {
  const [state, setState] = useState<RoleAssignmentState>({
    status: 'loading',
  });
  const [savingUserId, setSavingUserId] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  async function loadAssignments() {
    if (!supabase || !isSupabaseConfigured) {
      setState({
        status: 'error',
        message: 'Supabase is not configured.',
      });
      return;
    }

    const { data, error } = await supabase.rpc('get_league_role_assignments', {
      target_league_slug: leagueSlug,
    });

    if (error) {
      setState({ status: 'error', message: error.message });
      return;
    }

    setState({
      status: 'ready',
      users: ((data ?? []) as RoleAssignment[]).map((assignment) => ({
        ...assignment,
        role: assignment.role ?? null,
      })),
    });
  }

  useEffect(() => {
    void loadAssignments();
  }, []);

  async function saveRole(userId: string, role: LeagueRoleName | '') {
    if (!supabase || !isSupabaseConfigured || state.status !== 'ready') {
      return;
    }

    setSavingUserId(userId);

    const { error } = await supabase.rpc('set_league_member_role', {
      target_league_slug: leagueSlug,
      target_user_id: userId,
      target_role: role || null,
    });

    if (error) {
      setState({ status: 'error', message: error.message });
      setSavingUserId(null);
      return;
    }

    setState({
      status: 'ready',
      users: state.users.map((assignment) =>
        assignment.user_id === userId
          ? { ...assignment, role: role || null }
          : assignment,
      ),
    });
    setSavingUserId(null);
  }

  if (state.status === 'loading') {
    return (
      <p className="text-sm text-slate-600 dark:text-slate-300">
        Loading role assignments...
      </p>
    );
  }

  if (state.status === 'error') {
    return (
      <section>
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">
          Role assignment
        </h2>
        <p className="mt-4 rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300">
          {state.message}
        </p>
        <button
          type="button"
          onClick={() => {
            setState({ status: 'loading' });
            void loadAssignments();
          }}
          className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950"
        >
          Retry
        </button>
      </section>
    );
  }

  const normalizedSearchTerm = searchTerm.trim().toLowerCase();
  const filteredUsers = normalizedSearchTerm
    ? state.users.filter((assignment) =>
        [assignment.display_name, assignment.email]
          .filter(Boolean)
          .some((value) => value!.toLowerCase().includes(normalizedSearchTerm)),
      )
    : [];

  return (
    <section>
      <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">
        Role assignment
      </h2>
      <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
        Assign league roles to registered users.
      </p>

      <label className="mt-6 block max-w-xl text-sm font-medium text-slate-700 dark:text-slate-200">
        Search users
        <input
          type="search"
          value={searchTerm}
          onChange={(event) => setSearchTerm(event.target.value)}
          placeholder="Search by name or email"
          className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm text-slate-950 placeholder:text-slate-500 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100 dark:placeholder:text-slate-500"
        />
      </label>

      {state.users.length === 0 ? (
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          No registered users found.
        </p>
      ) : !normalizedSearchTerm ? (
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          Search for a registered user to assign a role.
        </p>
      ) : filteredUsers.length === 0 ? (
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          No users match your search.
        </p>
      ) : (
        <div className="mt-6 overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <ul className="divide-y divide-slate-200 dark:divide-slate-800">
            {filteredUsers.map((assignment) => (
              <li
                key={assignment.user_id}
                className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <p className="font-semibold text-slate-950 dark:text-white">
                    {assignment.display_name || assignment.email || 'Unknown user'}
                  </p>
                  {assignment.email ? (
                    <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
                      {assignment.email}
                    </p>
                  ) : null}
                </div>
                <label className="flex flex-col gap-1 text-sm font-medium text-slate-700 dark:text-slate-200">
                  Role
                  <select
                    value={assignment.role ?? ''}
                    disabled={savingUserId === assignment.user_id}
                    onChange={(event) => {
                      void saveRole(
                        assignment.user_id,
                        event.target.value as LeagueRoleName | '',
                      );
                    }}
                    className="min-h-11 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm text-slate-950 sm:w-44 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
                  >
                    {roleOptions.map((role) => (
                      <option key={role.value || 'none'} value={role.value}>
                        {role.label}
                      </option>
                    ))}
                  </select>
                </label>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
