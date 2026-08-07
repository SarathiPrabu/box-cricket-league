import { useEffect, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { BackButton } from '../../components/BackButton';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

const activeLeagueSlug = 'box-cricket-league';

type TeamDetail = {
  league_id: string;
  league_name: string;
  season_id: string;
  season_name: string;
  players_per_team: number;
  is_current: boolean;
  season_team_id: string;
  team_id: string;
  team_slug: string;
  team_name: string;
  manager_name: string | null;
  roster_count: number;
};

type RosterPlayer = {
  season_roster_id: string;
  player_id: string;
  player_slug: string;
  display_name: string;
  full_name: string | null;
  is_manager: boolean;
};

type TeamState =
    | { status: 'loading' }
    | { status: 'not-found' }
    | { status: 'error' }
    | { status: 'ready'; team: TeamDetail; roster: RosterPlayer[] };

function initials(value: string) {
  const parts = value.trim().split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] ?? 'T') + (parts[1]?.[0] ?? '')).toUpperCase();
}

function LoadingRoster() {
  return (
      <section>
        <div className="h-5 w-32 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {Array.from({ length: 6 }).map((_, index) => (
              <div
                  className="flex items-center gap-3 rounded-lg border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900"
                  key={index}
              >
                <div className="h-10 w-10 animate-pulse rounded-md bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
                <div className="min-w-0 flex-1 space-y-2">
                  <div className="h-4 w-2/3 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
                  <div className="h-3 w-1/3 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
                </div>
              </div>
          ))}
        </div>
      </section>
  );
}

export function TeamDetailPage() {
  const { slug } = useParams();
  const [searchParams] = useSearchParams();
  const [teamState, setTeamState] = useState<TeamState>({ status: 'loading' });

  const requestedSeasonSlug = searchParams.get('season');

  useEffect(() => {
    let cancelled = false;

    async function loadTeamRoster() {
      if (!slug || !supabase || !isSupabaseConfigured) {
        if (!cancelled) setTeamState({ status: 'error' });
        return;
      }

      setTeamState({ status: 'loading' });

      const { data: teamData, error: teamError } = await supabase.rpc('get_public_team_for_season', {
        target_league_slug: activeLeagueSlug,
        target_season_slug: requestedSeasonSlug,
        target_team_slug: slug,
      });
      const team = (teamData as TeamDetail[] | null)?.[0];

      if (teamError) {
        if (!cancelled) setTeamState({ status: 'error' });
        return;
      }

      if (!team) {
        if (!cancelled) setTeamState({ status: 'not-found' });
        return;
      }

      const { data: rosterData, error: rosterError } = await supabase.rpc('get_public_team_roster', {
        target_season_team_id: team.season_team_id,
      });

      if (!cancelled) {
        setTeamState(
            rosterError
                ? { status: 'error' }
                : {
                  status: 'ready',
                  team,
                  roster: (rosterData as RosterPlayer[] | null) ?? [],
                },
        );
      }
    }

    void loadTeamRoster();
    return () => {
      cancelled = true;
    };
  }, [requestedSeasonSlug, slug]);

  if (teamState.status === 'loading') {
    return (
        <div className="space-y-6">
          <BackButton />
          <header className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div className="h-7 w-48 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
            <div className="mt-3 h-4 w-64 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
          </header>
          <LoadingRoster />
        </div>
    );
  }

  if (teamState.status === 'not-found') {
    return (
        <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">Team not found</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            This team is not registered for the selected season.
          </p>
          <BackButton className="mt-4 inline-block" />
        </section>
    );
  }

  if (teamState.status === 'error') {
    return (
        <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">Unable to load team</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            Please try again in a moment.
          </p>
          <BackButton className="mt-4 inline-block" />
        </section>
    );
  }

  const { roster, team } = teamState;
  const managerName = team.manager_name?.trim() || 'Manager not assigned';

  return (
      <div className="space-y-6">
        <BackButton />

        <header className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-4">
              <div
                  aria-hidden="true"
                  className="flex h-16 w-16 shrink-0 items-center justify-center rounded-md border border-emerald-200 bg-emerald-50 text-xl font-bold text-emerald-800 dark:border-emerald-900/70 dark:bg-emerald-950 dark:text-emerald-200"
              >
                {initials(team.team_name)}
              </div>
              <div>
                <h2 className="break-words text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">{team.team_name}</h2>
                <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
                  {team.league_name} - {team.season_name}
                </p>
              </div>
            </div>

            <dl className="grid w-full grid-cols-1 gap-4 rounded-md bg-slate-50 p-4 text-sm sm:w-auto sm:grid-cols-2 dark:bg-slate-950">
              <div>
                <dt className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">Roster</dt>
                <dd className="mt-1 font-semibold text-slate-950 dark:text-white">
                  {team.roster_count}/{team.players_per_team}
                </dd>
              </div>
              <div>
                <dt className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">Manager</dt>
                <dd className="mt-1 font-semibold text-slate-950 dark:text-white">{managerName}</dd>
              </div>
            </dl>
          </div>
        </header>

        <section>
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h3 className="text-xl font-semibold text-slate-950 dark:text-white">Team roster</h3>
              <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
                Players assigned to this team for {team.season_name}.
              </p>
            </div>
            <span className="text-sm font-medium text-slate-600 dark:text-slate-300">{roster.length} players</span>
          </div>

          {roster.length === 0 ? (
              <p className="mt-4 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
                No players have been assigned to this team yet.
              </p>
          ) : (
              <ul className="mt-4 grid gap-3 sm:grid-cols-2">
                {roster.map((player) => (
                    <li key={player.season_roster_id}>
                      <Link
                          className="flex h-full items-center gap-3 rounded-lg border border-slate-200 bg-white p-4 shadow-sm transition hover:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500/50 motion-reduce:transition-none dark:border-slate-800 dark:bg-slate-900"
                          to={`/players/${player.player_slug}`}
                      >
                        <div
                            aria-hidden="true"
                            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-slate-100 text-sm font-bold text-slate-700 dark:bg-slate-800 dark:text-slate-200"
                        >
                          {initials(player.display_name)}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <p className="break-words font-semibold text-slate-950 dark:text-white">{player.display_name}</p>
                            {player.is_manager ? (
                                <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300">
                          Manager
                        </span>
                            ) : null}
                          </div>
                          {player.full_name && player.full_name !== player.display_name ? (
                              <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{player.full_name}</p>
                          ) : null}
                        </div>
                      </Link>
                    </li>
                ))}
              </ul>
          )}
        </section>
      </div>
  );
}
