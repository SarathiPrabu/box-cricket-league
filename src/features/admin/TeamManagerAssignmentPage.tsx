import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { SeasonSelector } from '../../components/SeasonSelector';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

const leagueSlug = 'box-cricket-league';

type Season = {
  league_id: string;
  league_name: string;
  season_id: string;
  season_name: string;
  starts_on: string | null;
  ends_on: string | null;
  is_current: boolean;
};

type RosterPlayer = {
  season_roster_id: string;
  player_id: string;
  display_name: string;
};

type EligibleUser = {
  user_id: string;
  display_name: string;
  email: string | null;
};

type TeamManagerAssignment = {
  season_team_id: string;
  team_id: string;
  team_name: string;
  manager_user_id: string | null;
  manager_user_name: string | null;
  manager_user_email: string | null;
  manager_player_id: string | null;
  manager_player_name: string | null;
  roster: RosterPlayer[];
  eligible_users: EligibleUser[];
};

type AssignmentState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; assignments: TeamManagerAssignment[] };

type DraftAssignment = {
  userId: string;
  playerId: string;
};

function seasonSlug(name: string) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function TeamManagerAssignmentPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [seasons, setSeasons] = useState<Season[] | null>(null);
  const [state, setState] = useState<AssignmentState>({ status: 'loading' });
  const [drafts, setDrafts] = useState<Record<string, DraftAssignment>>({});
  const [savingTeamId, setSavingTeamId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const requestedSeason = searchParams.get('season');
  const selectedSeason = useMemo(() => {
    if (!seasons?.length) return null;
    return seasons.find((season) => seasonSlug(season.season_name) === requestedSeason)
      ?? seasons.find((season) => season.is_current)
      ?? seasons[0];
  }, [requestedSeason, seasons]);

  const loadSeasons = useCallback(async () => {
    if (!supabase || !isSupabaseConfigured) {
      setState({ status: 'error', message: 'Supabase is not configured.' });
      return;
    }

    const { data, error: loadError } = await supabase.rpc('get_public_league_seasons', {
      target_league_slug: leagueSlug,
    });

    if (loadError) {
      setState({ status: 'error', message: loadError.message });
      return;
    }

    const loadedSeasons = (data as Season[] | null) ?? [];
    setSeasons(loadedSeasons);
    if (loadedSeasons.length === 0) {
      setState({ status: 'ready', assignments: [] });
    }
  }, []);

  const loadAssignments = useCallback(async (seasonId: string) => {
    if (!supabase || !isSupabaseConfigured) return;

    setState({ status: 'loading' });
    setError(null);

    const { data, error: loadError } = await supabase.rpc('get_team_manager_assignments', {
      target_season_id: seasonId,
    });

    if (loadError) {
      setState({ status: 'error', message: loadError.message });
      return;
    }

    const assignments = (data as TeamManagerAssignment[] | null) ?? [];
    setState({ status: 'ready', assignments });
    setDrafts(Object.fromEntries(assignments.map((assignment) => [
      assignment.season_team_id,
      {
        userId: assignment.manager_user_id ?? '',
        playerId: assignment.manager_player_id ?? '',
      },
    ])));
  }, []);

  useEffect(() => {
    void loadSeasons();
  }, [loadSeasons]);

  useEffect(() => {
    if (!selectedSeason) return;

    const selectedSlug = seasonSlug(selectedSeason.season_name);
    if (requestedSeason !== selectedSlug) {
      setSearchParams({ season: selectedSlug }, { replace: true });
    }

    void loadAssignments(selectedSeason.season_id);
  }, [loadAssignments, requestedSeason, selectedSeason, setSearchParams]);

  function updateDraft(teamId: string, key: keyof DraftAssignment, value: string) {
    setDrafts((current) => ({
      ...current,
      [teamId]: {
        ...current[teamId],
        [key]: value,
      },
    }));
  }

  async function saveAssignment(assignment: TeamManagerAssignment) {
    if (!supabase || state.status !== 'ready') return;

    const draft = drafts[assignment.season_team_id] ?? { userId: '', playerId: '' };
    const hasExisting = Boolean(assignment.manager_user_id || assignment.manager_player_id);
    const hasDraft = Boolean(draft.userId || draft.playerId);

    if (hasDraft && (!draft.userId || !draft.playerId)) {
      setError(`Choose both a registered user and a roster player for ${assignment.team_name}.`);
      return;
    }

    if (hasExisting && (draft.userId !== assignment.manager_user_id || draft.playerId !== assignment.manager_player_id)) {
      const confirmed = window.confirm(`Change the manager for ${assignment.team_name}?`);
      if (!confirmed) return;
    }

    setSavingTeamId(assignment.season_team_id);
    setError(null);

    const { error: saveError } = await supabase.rpc('set_season_team_manager', {
      target_season_team_id: assignment.season_team_id,
      target_user_id: draft.userId || null,
      target_player_id: draft.playerId || null,
    });

    setSavingTeamId(null);

    if (saveError) {
      setError(saveError.message);
      return;
    }

    if (selectedSeason) await loadAssignments(selectedSeason.season_id);
  }

  if (state.status === 'loading') {
    return <p className="text-sm text-slate-600 dark:text-slate-300">Loading team manager assignments...</p>;
  }

  if (state.status === 'error') {
    return (
      <section>
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Team managers</h2>
        <p className="mt-4 rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{state.message}</p>
        <button type="button" onClick={() => selectedSeason ? void loadAssignments(selectedSeason.season_id) : void loadSeasons()} className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950">Retry</button>
      </section>
    );
  }

  if (!selectedSeason || state.status !== 'ready') {
    return (
      <section>
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Team managers</h2>
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">No seasons are available for manager assignment.</p>
      </section>
    );
  }

  const eligibleUsers = state.assignments[0]?.eligible_users ?? [];

  return (
    <section>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Team managers</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Assign one registered team manager and roster player to each season team.</p>
        </div>
        <SeasonSelector
          id="team-manager-season-selector"
          seasons={seasons ?? []}
          selectedSeason={selectedSeason}
          onChange={(season) => setSearchParams({ season: seasonSlug(season.season_name) })}
        />
      </div>

      {error ? <p className="mt-6 rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{error}</p> : null}

      {eligibleUsers.length === 0 ? (
        <p className="mt-6 rounded-lg border border-amber-200 bg-amber-50 p-5 text-sm text-amber-800 dark:border-amber-900/70 dark:bg-amber-950/30 dark:text-amber-200">
          No registered users are available for assignment. Sign in a user first, then retry.
        </p>
      ) : null}

      <div className="mt-6 grid gap-4">
        {state.assignments.map((assignment) => {
          const draft = drafts[assignment.season_team_id] ?? { userId: '', playerId: '' };
          const saving = savingTeamId === assignment.season_team_id;

          return (
            <article key={assignment.season_team_id} className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
              <div className="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h3 className="text-lg font-semibold text-slate-950 dark:text-white">{assignment.team_name}</h3>
                  <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
                    Current manager: {assignment.manager_user_name || assignment.manager_player_name || 'Not assigned'}
                  </p>
                </div>
                <span className="text-sm text-slate-500 dark:text-slate-400">{assignment.roster.length} rostered players</span>
              </div>

              <div className="mt-4 grid gap-4 sm:grid-cols-2">
                <label className="text-sm font-medium text-slate-700 dark:text-slate-200">
                  Registered user
                  <select value={draft.userId} onChange={(event) => updateDraft(assignment.season_team_id, 'userId', event.target.value)} disabled={saving || eligibleUsers.length === 0} className="form-select mt-1">
                    <option value="">Unassigned</option>
                    {eligibleUsers.map((user) => <option key={user.user_id} value={user.user_id}>{user.display_name}{user.email ? ` (${user.email})` : ''}</option>)}
                  </select>
                </label>
                <label className="text-sm font-medium text-slate-700 dark:text-slate-200">
                  Roster player
                  <select value={draft.playerId} onChange={(event) => updateDraft(assignment.season_team_id, 'playerId', event.target.value)} disabled={saving || assignment.roster.length === 0} className="form-select mt-1">
                    <option value="">Unassigned</option>
                    {assignment.roster.map((player) => <option key={player.player_id} value={player.player_id}>{player.display_name}</option>)}
                  </select>
                </label>
              </div>

              <div className="mt-4 flex flex-wrap items-center gap-3">
                <button type="button" disabled={saving} onClick={() => void saveAssignment(assignment)} className="min-h-11 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 disabled:cursor-not-allowed disabled:opacity-60">{saving ? 'Saving...' : 'Save manager'}</button>
                <span className="text-xs text-slate-500 dark:text-slate-400">Role checks are disabled for testing.</span>
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
