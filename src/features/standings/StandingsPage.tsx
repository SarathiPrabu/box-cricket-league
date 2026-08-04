import { useEffect, useMemo, useState } from 'react';
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

type StandingRow = {
  season_team_id: string;
  team_id: string;
  team_slug: string;
  team_name: string;
  matches_played: number;
  wins: number;
  losses: number;
  draws: number;
  points: number;
  runs_for: number;
  balls_faced: number;
  runs_against: number;
  balls_bowled: number;
  net_run_rate: number;
};

type SeasonsState =
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; seasons: Season[] };

type StandingsState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; standings: StandingRow[] };

function seasonSlug(name: string) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function formatNrr(value: number) {
  return value.toFixed(3);
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
      <label className="block text-sm font-medium text-slate-700 dark:text-slate-200" htmlFor="standings-season-selector">
        Season
      </label>
      <select
        className="mt-2 w-full rounded-md border border-slate-300 bg-white px-3 py-3 text-sm font-medium text-slate-950 shadow-sm transition focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500/40 dark:border-slate-700 dark:bg-slate-900 dark:text-white"
        id="standings-season-selector"
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

function TeamBadge({ teamName }: { teamName: string }) {
  const initials = teamName
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0] ?? '')
    .join('')
    .toUpperCase();

  return (
    <div
      aria-hidden="true"
      className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-emerald-200 bg-emerald-50 text-sm font-bold text-emerald-800 dark:border-emerald-900/70 dark:bg-emerald-950 dark:text-emerald-200"
    >
      {initials || 'T'}
    </div>
  );
}

function StandingsRow({
  row,
  selectedSeason,
}: {
  row: StandingRow;
  selectedSeason: Season;
}) {
  const teamUrl = `/teams/${row.team_slug}?season=${encodeURIComponent(seasonSlug(selectedSeason.season_name))}`;

  return (
    <tr className="border-t border-slate-200 transition hover:bg-emerald-50/50 motion-reduce:transition-none dark:border-slate-800 dark:hover:bg-emerald-950/20">
      <td className="px-4 py-3 sm:px-6">
        <Link
          aria-label={`Open ${row.team_name} roster for ${selectedSeason.season_name}`}
          className="flex min-w-52 items-center gap-3 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-brand-500/50"
          to={teamUrl}
        >
          <TeamBadge teamName={row.team_name} />
          <span className="font-semibold text-slate-950 hover:text-brand-700 dark:text-white dark:hover:text-brand-400">
            {row.team_name}
          </span>
        </Link>
      </td>
      <td className="px-4 py-3 text-center text-sm text-slate-700 sm:px-6 dark:text-slate-300">{row.matches_played}</td>
      <td className="px-4 py-3 text-center text-sm text-slate-700 sm:px-6 dark:text-slate-300">{row.wins}</td>
      <td className="px-4 py-3 text-center text-sm text-slate-700 sm:px-6 dark:text-slate-300">{row.losses}</td>
      <td className="px-4 py-3 text-center text-sm text-slate-700 sm:px-6 dark:text-slate-300">{row.draws}</td>
      <td className="px-4 py-3 text-center text-sm font-semibold text-slate-950 sm:px-6 dark:text-white">{row.points}</td>
      <td className="px-4 py-3 text-center text-sm font-semibold text-slate-950 sm:px-6 dark:text-white">
        {formatNrr(row.net_run_rate)}
      </td>
    </tr>
  );
}

function StandingsTable({
  standings,
  selectedSeason,
  loading = false,
}: {
  standings?: StandingRow[];
  selectedSeason?: Season;
  loading?: boolean;
}) {
  return (
    <div className="mt-6 overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[820px] border-collapse text-left">
          <thead className="bg-slate-50 dark:bg-slate-950/60">
            <tr>
              <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                Team
              </th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                M
              </th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                W
              </th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                L
              </th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                T/NR
              </th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                Pts
              </th>
              <th className="px-4 py-3 text-center text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300" scope="col">
                NRR
              </th>
            </tr>
          </thead>
          <tbody>
            {loading
              ? Array.from({ length: 6 }).map((_, index) => (
                  <tr className="border-t border-slate-200 dark:border-slate-800" key={index}>
                    <td className="px-4 py-3 sm:px-6">
                      <div className="flex items-center gap-3">
                        <div className="h-10 w-10 shrink-0 animate-pulse rounded-md bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
                        <div className="h-4 w-36 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
                      </div>
                    </td>
                    {Array.from({ length: 6 }).map((__, cellIndex) => (
                      <td className="px-4 py-3 sm:px-6" key={cellIndex}>
                        <div className="mx-auto h-4 w-10 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
                      </td>
                    ))}
                  </tr>
                ))
              : standings && selectedSeason
                ? standings.map((row) => (
                    <StandingsRow key={row.season_team_id} row={row} selectedSeason={selectedSeason} />
                  ))
                : null}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function StandingsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [seasonsState, setSeasonsState] = useState<SeasonsState>({ status: 'loading' });
  const [standingsState, setStandingsState] = useState<StandingsState>({ status: 'idle' });

  const requestedSeasonSlug = searchParams.get('season');

  useEffect(() => {
    let cancelled = false;

    async function loadSeasons() {
      setSeasonsState({ status: 'loading' });

      if (!supabase || !isSupabaseConfigured) {
        if (!cancelled) setSeasonsState({ status: 'error' });
        return;
      }

      const { data, error } = await supabase.rpc('get_public_league_seasons', {
        target_league_slug: activeLeagueSlug,
      });

      if (!cancelled) {
        setSeasonsState(
          error ? { status: 'error' } : { status: 'ready', seasons: (data as Season[] | null) ?? [] },
        );
      }
    }

    void loadSeasons();
    return () => {
      cancelled = true;
    };
  }, []);

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

  useEffect(() => {
    let cancelled = false;

    async function loadStandings(season: Season) {
      setStandingsState({ status: 'loading' });

      if (!supabase || !isSupabaseConfigured) {
        if (!cancelled) setStandingsState({ status: 'error' });
        return;
      }

      const { data, error } = await supabase.rpc('get_public_season_standings', {
        target_season_id: season.season_id,
      });

      if (!cancelled) {
        setStandingsState(
          error ? { status: 'error' } : { status: 'ready', standings: (data as StandingRow[] | null) ?? [] },
        );
      }
    }

    if (selectedSeason) {
      void loadStandings(selectedSeason);
    }

    return () => {
      cancelled = true;
    };
  }, [selectedSeason]);

  if (seasonsState.status === 'loading') {
    return (
      <section>
        <h2 className="text-3xl font-semibold text-slate-950 dark:text-white">Standings</h2>
        <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Loading league seasons.</p>
        <StandingsTable loading />
      </section>
    );
  }

  if (seasonsState.status === 'error') {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">Unable to load standings</h2>
        <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Please try again in a moment.</p>
      </section>
    );
  }

  if (!selectedSeason) {
    return (
      <section>
        <h2 className="text-3xl font-semibold text-slate-950 dark:text-white">Standings</h2>
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
          <h2 className="text-3xl font-semibold text-slate-950 dark:text-white">Standings</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            View season standings for {leagueName}. Points use a standard 2 for a win, 1 for a tie/no result, 0 for a loss
            system. NRR breaks tied points.
          </p>
        </div>
        <SeasonSelector
          onChange={(season) => setSearchParams({ season: seasonSlug(season.season_name) })}
          seasons={seasonsState.seasons}
          selectedSeason={selectedSeason}
        />
      </div>

      {standingsState.status === 'loading' || standingsState.status === 'idle' ? <StandingsTable loading /> : null}

      {standingsState.status === 'error' ? (
        <div className="mt-6 rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <p className="text-sm text-slate-600 dark:text-slate-300">Unable to load standings right now.</p>
        </div>
      ) : null}

      {standingsState.status === 'ready' && standingsState.standings.length === 0 ? (
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          No completed matches have been recorded for this season yet.
        </p>
      ) : null}

      {standingsState.status === 'ready' && standingsState.standings.length > 0 ? (
        <StandingsTable selectedSeason={selectedSeason} standings={standingsState.standings} />
      ) : null}
    </section>
  );
}
