import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { SeasonSelector } from '../../components/SeasonSelector';
import { InfoCard } from '../../components/StandingsTable';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

const activeLeagueSlug = 'box-cricket-league';
const leaderboardLimit = 5;

type Season = {
  league_id: string;
  league_name: string;
  season_id: string;
  season_name: string;
  starts_on: string | null;
  ends_on: string | null;
  is_current: boolean;
};

type LeaderboardRow = {
  player_id: string;
  player_slug: string;
  player_name: string;
  team_name: string | null;
  matches_played: number;
  runs: number;
  balls_faced: number;
  fours: number;
  sixes: number;
  balls_bowled: number;
  dot_balls_bowled: number;
  runs_conceded: number;
  wickets: number;
  catches: number;
  stumpings: number;
  player_of_match_count: number;
};

type SeasonsState =
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; seasons: Season[] };

type LeaderboardsState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; rows: LeaderboardRow[] };

type LeaderboardDefinition = {
  title: string;
  description: string;
  valueLabel: string;
  value: (row: LeaderboardRow) => number;
  formatValue?: (row: LeaderboardRow) => string;
  isEligible?: (row: LeaderboardRow) => boolean;
  sortAscending?: boolean;
  secondaryLabel?: string;
  secondaryValue?: (row: LeaderboardRow) => string;
};

function seasonSlug(name: string) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

function formatRate(numerator: number, denominator: number, multiplier: number) {
  return denominator === 0 ? '—' : ((numerator / denominator) * multiplier).toFixed(2);
}

function formatMatches(matches: number) {
  return `${matches} ${matches === 1 ? 'match' : 'matches'}`;
}

const leaderboardDefinitions: LeaderboardDefinition[] = [
  {
    title: 'Most runs',
    description: 'Top batting scores',
    valueLabel: 'Runs',
    value: (row) => row.runs,
    secondaryLabel: 'Strike rate',
    secondaryValue: (row) => formatRate(row.runs, row.balls_faced, 100),
  },
  {
    title: 'Most wickets',
    description: 'Top bowling performances',
    valueLabel: 'Wickets',
    value: (row) => row.wickets,
    secondaryLabel: 'Economy',
    secondaryValue: (row) => formatRate(row.runs_conceded, row.balls_bowled, 6),
  },
  {
    title: 'Best economy',
    description: 'Most economical bowlers',
    valueLabel: 'Economy',
    value: (row) => (row.runs_conceded / row.balls_bowled) * 6,
    formatValue: (row) => formatRate(row.runs_conceded, row.balls_bowled, 6),
    isEligible: (row) => row.balls_bowled > 0,
    sortAscending: true,
  },
  // Temporarily hidden from the frontend; the database value remains available.
  // {
  //   title: 'Most dot balls',
  //   description: 'Most scoreless balls bowled',
  //   valueLabel: 'Dot balls',
  //   value: (row) => row.dot_balls_bowled,
  // },
  {
    title: 'Most catches',
    description: 'Leading fielders',
    valueLabel: 'Catches',
    value: (row) => row.catches,
  },
  {
    title: 'Most fours',
    description: 'Most boundary fours',
    valueLabel: 'Fours',
    value: (row) => row.fours,
  },
  {
    title: 'Most sixes',
    description: 'Most maximums',
    valueLabel: 'Sixes',
    value: (row) => row.sixes,
  },
  {
    title: 'Player of the Match',
    description: 'Most match awards',
    valueLabel: 'Awards',
    value: (row) => row.player_of_match_count,
  },
];

function topRows(rows: LeaderboardRow[], definition: LeaderboardDefinition) {
  return rows
    .filter((row) => definition.isEligible?.(row) ?? definition.value(row) > 0)
    .sort((first, second) => {
      const valueDifference = definition.sortAscending
        ? definition.value(first) - definition.value(second)
        : definition.value(second) - definition.value(first);
      return valueDifference || first.player_name.localeCompare(second.player_name);
    })
    .slice(0, leaderboardLimit);
}

function LeaderboardCard({
  definition,
  rows,
  loading = false,
}: {
  definition: LeaderboardDefinition;
  rows?: LeaderboardRow[];
  loading?: boolean;
}) {
  const leaders = rows ? topRows(rows, definition) : [];

  return (
    <section className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <header className="border-b border-slate-200 px-4 py-4 dark:border-slate-800">
        <h3 className="text-lg font-semibold text-slate-950 dark:text-white">{definition.title}</h3>
        <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{definition.description}</p>
      </header>

      {loading ? (
        <ol aria-label={`Loading ${definition.title.toLowerCase()}`}>
          {Array.from({ length: leaderboardLimit }).map((_, index) => (
            <li className="flex items-center gap-3 border-t border-slate-200 px-4 py-3 first:border-t-0 dark:border-slate-800" key={index}>
              <span className="h-4 w-5 animate-pulse rounded bg-slate-200 dark:bg-slate-700" />
              <span className="h-4 flex-1 animate-pulse rounded bg-slate-200 dark:bg-slate-700" />
              <span className="h-5 w-12 animate-pulse rounded bg-slate-200 dark:bg-slate-700" />
            </li>
          ))}
        </ol>
      ) : leaders.length === 0 ? (
        <p className="px-4 py-5 text-sm text-slate-600 dark:text-slate-300">
          No recorded {definition.title.toLowerCase()} for this season yet.
        </p>
      ) : (
        <ol>
          {leaders.map((row, index) => (
            <li className="flex items-center gap-3 border-t border-slate-200 px-4 py-3 first:border-t-0 dark:border-slate-800" key={row.player_id}>
              <span className="w-5 shrink-0 text-sm font-semibold text-slate-500 dark:text-slate-400">{index + 1}</span>
              <div className="min-w-0 flex-1">
                <Link
                  className="block truncate font-semibold text-slate-950 hover:text-brand-700 dark:text-white dark:hover:text-brand-400"
                  to={`/players/${row.player_slug}`}
                >
                  {row.player_name}
                </Link>
                <p className="mt-0.5 truncate text-sm text-slate-600 dark:text-slate-300">
                  {row.team_name ?? 'Team not recorded'}
                </p>
              </div>
              <div className="shrink-0 text-right">
                <p className="font-semibold text-slate-950 dark:text-white">
                  {definition.formatValue ? definition.formatValue(row) : definition.value(row)}{' '}
                  <span className="text-xs font-medium text-slate-500 dark:text-slate-400">{definition.valueLabel}</span>
                </p>
                <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                  {definition.secondaryLabel && definition.secondaryValue
                    ? `${definition.secondaryLabel} ${definition.secondaryValue(row)} · `
                    : null}
                  {formatMatches(row.matches_played)}
                </p>
              </div>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

function LeaderboardGrid({
  rows,
  loading = false,
  showDotBalls,
}: {
  rows?: LeaderboardRow[];
  loading?: boolean;
  showDotBalls: boolean;
}) {
  const definitions = showDotBalls
    ? leaderboardDefinitions
    : leaderboardDefinitions.filter((definition) => definition.title !== 'Most dot balls');

  return (
    <div className="mt-6 grid gap-4 md:grid-cols-2">
      {definitions.map((definition) => (
        <LeaderboardCard definition={definition} key={definition.title} loading={loading} rows={rows} />
      ))}
    </div>
  );
}

export function LeaderboardsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [seasonsState, setSeasonsState] = useState<SeasonsState>({ status: 'loading' });
  const [leaderboardsState, setLeaderboardsState] = useState<LeaderboardsState>({ status: 'idle' });
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

    async function loadLeaderboards(season: Season) {
      setLeaderboardsState({ status: 'loading' });

      if (!supabase || !isSupabaseConfigured) {
        if (!cancelled) setLeaderboardsState({ status: 'error' });
        return;
      }

      const { data, error } = await supabase.rpc('get_public_season_leaderboards', {
        target_season_id: season.season_id,
      });

      if (!cancelled) {
        setLeaderboardsState(
          error
            ? { status: 'error' }
            : { status: 'ready', rows: (data as LeaderboardRow[] | null) ?? [] },
        );
      }
    }

    if (selectedSeason) {
      void loadLeaderboards(selectedSeason);
    }

    return () => {
      cancelled = true;
    };
  }, [selectedSeason]);

  if (seasonsState.status === 'loading') {
    return (
      <section>
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Leaderboards</h2>
        <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Loading league seasons.</p>
        <LeaderboardGrid loading showDotBalls={false} />
      </section>
    );
  }

  if (seasonsState.status === 'error') {
    return <InfoCard message="Please try again in a moment." title="Unable to load leaderboards" />;
  }

  if (!selectedSeason) {
    return (
      <section>
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Leaderboards</h2>
        <InfoCard className="mt-6" message="No seasons are available for this league." />
      </section>
    );
  }

  const leagueName = seasonsState.seasons[0]?.league_name ?? 'Box Cricket League';
  const showDotBalls = seasonSlug(selectedSeason.season_name) !== 'season-1';

  return (
    <section>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Leaderboards</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            {leagueName} {selectedSeason.season_name} season leaders.
          </p>
        </div>
        <SeasonSelector
          id="leaderboards-season-selector"
          onChange={(season) => setSearchParams({ season: seasonSlug(season.season_name) })}
          seasons={seasonsState.seasons}
          selectedSeason={selectedSeason}
        />
      </div>

      {leaderboardsState.status === 'loading' || leaderboardsState.status === 'idle' ? (
        <LeaderboardGrid loading showDotBalls={showDotBalls} />
      ) : null}

      {leaderboardsState.status === 'error' ? (
        <InfoCard className="mt-6" message="Unable to load leaderboards right now." />
      ) : null}

      {leaderboardsState.status === 'ready' ? (
        <LeaderboardGrid rows={leaderboardsState.rows} showDotBalls={showDotBalls} />
      ) : null}
    </section>
  );
}
