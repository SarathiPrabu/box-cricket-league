import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

const activeLeagueSlug = 'box-cricket-league';

type Season = {
  league_id: string;
  league_name: string;
  season_id: string;
  season_name: string;
  starts_on: string | null;
  ends_on: string | null;
  is_current: boolean;
};

type Team = {
  season_team_id: string;
  team_id: string;
  team_slug: string;
  team_name: string;
  manager_name: string | null;
};

type SeasonsState =
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; seasons: Season[] };

type TeamsState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; teams: Team[] };

function seasonSlug(name: string) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function initials(value: string) {
  const parts = value.trim().split(/\s+/).filter(Boolean);
  return (parts[0]?.[0] ?? 'T') + (parts[1]?.[0] ?? '');
}

function SeasonSelector({
  seasons,
  selectedSeason,
  onChange,
}: {
  seasons: Season[];
  selectedSeason: Season;
  onChange: (season: Season) => void;
}) {
  return (
    <div className="mt-5 max-w-xs">
      <label className="block text-sm font-medium text-slate-700 dark:text-slate-200" htmlFor="season-selector">
        Season
      </label>
      <select
        className="mt-2 w-full rounded-md border border-slate-300 bg-white px-3 py-3 text-sm font-medium text-slate-950 shadow-sm transition focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500/40 dark:border-slate-700 dark:bg-slate-900 dark:text-white"
        id="season-selector"
        onChange={(event) => {
          const nextSeason = seasons.find((season) => season.season_id === event.target.value);
          if (nextSeason) onChange(nextSeason);
        }}
        value={selectedSeason.season_id}
      >
        {seasons.map((season) => (
          <option key={season.season_id} value={season.season_id}>
            {season.season_name}
          </option>
        ))}
      </select>
    </div>
  );
}

function TeamLogo({ teamName }: { teamName: string }) {
  return (
    <div
      aria-hidden="true"
      className="flex h-14 w-14 shrink-0 items-center justify-center rounded-md border border-emerald-200 bg-emerald-50 text-lg font-bold text-emerald-800 dark:border-emerald-900/70 dark:bg-emerald-950 dark:text-emerald-200"
    >
      {initials(teamName).toUpperCase()}
    </div>
  );
}

function TeamCard({ team, selectedSeason }: { team: Team; selectedSeason: Season }) {
  const managerName = team.manager_name?.trim() || 'Manager not assigned';
  const teamUrl = `/teams/${team.team_slug}?season=${encodeURIComponent(seasonSlug(selectedSeason.season_name))}`;

  return (
    <li>
      <Link
        aria-label={`Open ${team.team_name} details for ${selectedSeason.season_name}`}
        className="group flex h-full min-h-32 items-center gap-4 rounded-lg border border-slate-200 bg-white p-4 shadow-sm outline-none transition hover:border-brand-500 hover:bg-emerald-50/40 focus-visible:border-brand-600 focus-visible:ring-2 focus-visible:ring-brand-500/50 active:scale-[0.99] motion-reduce:transition-none motion-reduce:active:scale-100 dark:border-slate-800 dark:bg-slate-900 dark:hover:border-brand-500 dark:hover:bg-slate-900/80"
        to={teamUrl}
      >
        <TeamLogo teamName={team.team_name} />
        <div className="min-w-0 flex-1">
          <p className="break-words text-base font-semibold text-slate-950 dark:text-white">{team.team_name}</p>
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
            <span className="font-medium text-slate-700 dark:text-slate-200">Manager:</span> {managerName}
          </p>
          <p className="mt-3 text-xs font-semibold uppercase tracking-wide text-brand-600 dark:text-brand-400">
            Open team
          </p>
        </div>
        <span
          aria-hidden="true"
          className="text-xl text-slate-400 transition group-hover:translate-x-0.5 group-hover:text-brand-600 motion-reduce:transition-none motion-reduce:group-hover:translate-x-0 dark:text-slate-500 dark:group-hover:text-brand-400"
        >
          →
        </span>
      </Link>
    </li>
  );
}

function TeamCardSkeleton() {
  return (
    <li className="flex min-h-32 items-center gap-4 rounded-lg border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <div className="h-14 w-14 shrink-0 animate-pulse rounded-md bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
      <div className="min-w-0 flex-1 space-y-3">
        <div className="h-4 w-3/4 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
        <div className="h-3 w-1/2 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
        <div className="h-3 w-20 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
      </div>
    </li>
  );
}

export function TeamsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [seasonsState, setSeasonsState] = useState<SeasonsState>({ status: 'loading' });
  const [teamsState, setTeamsState] = useState<TeamsState>({ status: 'idle' });

  const requestedSeasonSlug = searchParams.get('season');

  const loadSeasons = useCallback(async () => {
    setSeasonsState({ status: 'loading' });

    if (!supabase || !isSupabaseConfigured) {
      setSeasonsState({ status: 'error' });
      return;
    }

    const { data, error } = await supabase.rpc('get_public_league_seasons', {
      target_league_slug: activeLeagueSlug,
    });

    setSeasonsState(
      error
        ? { status: 'error' }
        : { status: 'ready', seasons: (data as Season[] | null) ?? [] },
    );
  }, []);

  useEffect(() => {
    void loadSeasons();
  }, [loadSeasons]);

  const selectedSeason = useMemo(() => {
    if (seasonsState.status !== 'ready' || seasonsState.seasons.length === 0) return null;

    return (
      seasonsState.seasons.find((season) => seasonSlug(season.season_name) === requestedSeasonSlug) ??
      seasonsState.seasons.find((season) => season.is_current) ??
      seasonsState.seasons[0]
    );
  }, [requestedSeasonSlug, seasonsState]);

  useEffect(() => {
    if (!selectedSeason) return;

    const selectedSlug = seasonSlug(selectedSeason.season_name);
    if (requestedSeasonSlug === selectedSlug) return;

    setSearchParams({ season: selectedSlug }, { replace: true });
  }, [requestedSeasonSlug, selectedSeason, setSearchParams]);

  const loadTeams = useCallback(async (season: Season) => {
    setTeamsState({ status: 'loading' });

    if (!supabase || !isSupabaseConfigured) {
      setTeamsState({ status: 'error' });
      return;
    }

    const { data, error } = await supabase.rpc('get_public_teams_for_season', {
      target_season_id: season.season_id,
    });

    setTeamsState(
      error
        ? { status: 'error' }
        : { status: 'ready', teams: (data as Team[] | null) ?? [] },
    );
  }, []);

  useEffect(() => {
    if (!selectedSeason) return;
    void loadTeams(selectedSeason);
  }, [loadTeams, selectedSeason]);

  if (seasonsState.status === 'loading') {
    return (
      <section>
        <h2 className="text-3xl font-semibold text-slate-950 dark:text-white">Teams</h2>
        <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Loading league seasons.</p>
        <ul className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4" aria-label="Loading teams">
          {Array.from({ length: 6 }).map((_, index) => (
            <TeamCardSkeleton key={index} />
          ))}
        </ul>
      </section>
    );
  }

  if (seasonsState.status === 'error') {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">Unable to load teams</h2>
        <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Please try again in a moment.</p>
        <button
          className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-brand-400 focus:outline-none focus:ring-2 focus:ring-brand-500/50 motion-reduce:transition-none"
          onClick={() => void loadSeasons()}
          type="button"
        >
          Retry
        </button>
      </section>
    );
  }

  if (!selectedSeason) {
    return (
      <section>
        <h2 className="text-3xl font-semibold text-slate-950 dark:text-white">Teams</h2>
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          No seasons are available for this league.
        </p>
      </section>
    );
  }

  const leagueName = seasonsState.seasons[0]?.league_name ?? 'Box Cricket League';

  return (
    <section>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-3xl font-semibold text-slate-950 dark:text-white">Teams</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            Browse teams in {leagueName}.
          </p>
        </div>
        <SeasonSelector
          onChange={(season) => setSearchParams({ season: seasonSlug(season.season_name) })}
          seasons={seasonsState.seasons}
          selectedSeason={selectedSeason}
        />
      </div>

      {teamsState.status === 'loading' || teamsState.status === 'idle' ? (
        <ul className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4" aria-label="Loading teams">
          {Array.from({ length: 6 }).map((_, index) => (
            <TeamCardSkeleton key={index} />
          ))}
        </ul>
      ) : null}

      {teamsState.status === 'error' ? (
        <div className="mt-6 rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <p className="text-sm text-slate-600 dark:text-slate-300">Unable to load teams right now.</p>
          <button
            className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-brand-400 focus:outline-none focus:ring-2 focus:ring-brand-500/50 motion-reduce:transition-none"
            onClick={() => void loadTeams(selectedSeason)}
            type="button"
          >
            Retry
          </button>
        </div>
      ) : null}

      {teamsState.status === 'ready' && teamsState.teams.length === 0 ? (
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          No teams are registered for this season.
        </p>
      ) : null}

      {teamsState.status === 'ready' && teamsState.teams.length > 0 ? (
        <ul className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {teamsState.teams.map((team) => (
            <TeamCard key={team.season_team_id} selectedSeason={selectedSeason} team={team} />
          ))}
        </ul>
      ) : null}
    </section>
  );
}
