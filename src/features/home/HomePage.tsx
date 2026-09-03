import { useEffect, useState } from 'react';
import { MatchRail } from './MatchRail';
import type { HomeMatchData } from '../../components/HomeMatchCard';
import type { MatchScoringState, ScoringInnings } from '../matches/liveMatchTypes';
import type { MatchCardData } from '../../components/MatchCard';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

const leagueSlug = 'box-cricket-league';
const scoreRequestBatchSize = 4;

type Season = {
  league_name: string;
  season_id: string;
  season_name: string;
  is_current: boolean;
};

type PublicMatch = MatchCardData & {
  home_season_team_id: string;
  away_season_team_id: string;
};

type HomeState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | {
      status: 'ready';
      seasonName: string;
      matches: HomeMatchData[];
    };

function HomeLoading() {
  return (
    <section aria-busy="true" aria-label="Loading fixtures and results">
      <span className="sr-only" role="status">Loading fixtures and results.</span>
      <div aria-hidden="true" className="home-match-rail__loading mt-8">
        {Array.from({ length: 2 }).map((_, index) => (
          <div className="home-match-rail__skeleton" key={index}>
            <span />
            <span />
            <span />
          </div>
        ))}
      </div>
    </section>
  );
}

function matchTimestamp(value: string | null) {
  if (!value) return Number.POSITIVE_INFINITY;

  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? Number.POSITIVE_INFINITY : timestamp;
}

function summarizeInnings(innings: ScoringInnings | undefined) {
  if (!innings) {
    return { runs: null, wickets: null, legalBalls: null, ballsPerOver: null };
  }

  const deliveries = innings.overs.flatMap((over) => over.deliveries);
  return {
    runs: deliveries.reduce((total, delivery) => total + delivery.batter_runs + delivery.extra_runs, 0),
    wickets: new Set(deliveries.map((delivery) => delivery.dismissed_season_roster_id).filter(Boolean)).size,
    legalBalls: deliveries.filter((delivery) => delivery.delivery_type === 'legal').length,
    ballsPerOver: innings.balls_per_over,
  };
}

function getWinMargin(
  match: PublicMatch,
  scoringState: MatchScoringState,
  home: ReturnType<typeof summarizeInnings>,
  away: ReturnType<typeof summarizeInnings>,
): HomeMatchData['win_margin'] {
  if (match.result_type !== 'win' || !match.winner_team_name) return null;
  if (home.runs === null || away.runs === null) return null;

  const firstInnings = scoringState.innings.find((innings) => innings.innings_number === 1);
  const winnerTeamId = scoringState.match.winner_season_team_id;
  if (!firstInnings || !winnerTeamId) return null;

  if (firstInnings.batting_season_team_id === winnerTeamId) {
    const amount = Math.abs(home.runs - away.runs);
    return amount > 0 ? { amount, type: 'run' } : null;
  }

  const winnerWickets = winnerTeamId === match.home_season_team_id ? home.wickets : away.wickets;
  if (winnerWickets === null) return null;

  const lineupSize = scoringState.lineups.filter((player) => player.season_team_id === winnerTeamId).length;
  const amount = Math.max(lineupSize - winnerWickets, 0);
  return amount > 0 ? { amount, type: 'wicket' } : null;
}

async function addScoreSummaries(matches: PublicMatch[]) {
  if (!supabase) return [];
  const client = supabase;
  const summaries: HomeMatchData[] = [];

  for (let index = 0; index < matches.length; index += scoreRequestBatchSize) {
    const batch = matches.slice(index, index + scoreRequestBatchSize);
    const batchSummaries = await Promise.all(batch.map(async (match): Promise<HomeMatchData> => {
      const emptySummary: HomeMatchData = {
        ...match,
        home_runs: null,
        home_wickets: null,
        home_legal_balls: null,
        home_balls_per_over: null,
        away_runs: null,
        away_wickets: null,
        away_legal_balls: null,
        away_balls_per_over: null,
        win_margin: null,
      };

      if (match.status !== 'live' && match.status !== 'completed') return emptySummary;

      try {
        const scoringResult = await client.rpc('get_match_scoring_state', {
          target_match_id: match.match_id,
        });
        if (scoringResult.error || !scoringResult.data) return emptySummary;

        const scoringState = scoringResult.data as MatchScoringState;
        const home = summarizeInnings(scoringState.innings.find((innings) => innings.batting_season_team_id === match.home_season_team_id));
        const away = summarizeInnings(scoringState.innings.find((innings) => innings.batting_season_team_id === match.away_season_team_id));

        return {
          ...match,
          home_runs: home.runs,
          home_wickets: home.wickets,
          home_legal_balls: home.legalBalls,
          home_balls_per_over: home.ballsPerOver,
          away_runs: away.runs,
          away_wickets: away.wickets,
          away_legal_balls: away.legalBalls,
          away_balls_per_over: away.ballsPerOver,
          win_margin: getWinMargin(match, scoringState, home, away),
        };
      } catch {
        return emptySummary;
      }
    }));

    summaries.push(...batchSummaries);
  }

  return summaries;
}

function orderMatches(matches: HomeMatchData[]) {
  const visibleMatches = matches.filter((match) => match.status !== 'draft' && match.status !== 'cancelled');
  const statusOrder: Record<HomeMatchData['status'], number> = {
    live: 0,
    scheduled: 1,
    completed: 2,
    draft: 3,
    cancelled: 3,
  };

  return [...visibleMatches].sort((first, second) => {
    const statusDifference = statusOrder[first.status] - statusOrder[second.status];
    if (statusDifference !== 0) return statusDifference;

    const firstTimestamp = matchTimestamp(first.match_date);
    const secondTimestamp = matchTimestamp(second.match_date);
    return first.status === 'completed'
      ? secondTimestamp - firstTimestamp
      : firstTimestamp - secondTimestamp;
  });
}

export function HomePage() {
  const [state, setState] = useState<HomeState>({ status: 'loading' });
  const [retryCount, setRetryCount] = useState(0);

  useEffect(() => {
    let cancelled = false;

    async function loadHome() {
      setState({ status: 'loading' });

      if (!supabase || !isSupabaseConfigured) {
        if (!cancelled) setState({ status: 'error', message: 'Supabase is not configured.' });
        return;
      }

      const seasonsResult = await supabase.rpc('get_public_league_seasons', {
        target_league_slug: leagueSlug,
      });

      if (cancelled) return;
      if (seasonsResult.error) {
        setState({ status: 'error', message: 'Unable to load league seasons right now.' });
        return;
      }

      const seasons = (seasonsResult.data as Season[] | null) ?? [];
      const selectedSeason = seasons.find((season) => season.is_current) ?? seasons[0];

      if (!selectedSeason) {
        setState({
          status: 'ready',
          seasonName: '',
          matches: [],
        });
        return;
      }

      const matchesResult = await supabase.rpc('get_public_matches_for_season', {
        target_season_id: selectedSeason.season_id,
      });

      if (cancelled) return;
      if (matchesResult.error) {
        setState({ status: 'error', message: 'Unable to load fixtures and results right now.' });
        return;
      }

      try {
        const publicMatches = (matchesResult.data as PublicMatch[] | null) ?? [];
        const visibleMatches = publicMatches.filter((match) => match.status !== 'draft' && match.status !== 'cancelled');
        const matches = await addScoreSummaries(visibleMatches);
        if (!cancelled) {
          setState({
            status: 'ready',
            seasonName: selectedSeason.season_name,
            matches: orderMatches(matches),
          });
        }
      } catch {
        if (!cancelled) setState({ status: 'error', message: 'Unable to load match scores right now.' });
      }
    }

    void loadHome();

    return () => {
      cancelled = true;
    };
  }, [retryCount]);

  if (state.status === 'loading') {
    return <HomeLoading />;
  }

  if (state.status === 'error') {
    return (
      <section>
        <div className="mt-8 rounded-lg border border-red-200 bg-red-50 p-5 dark:border-red-900 dark:bg-red-950/30" role="alert">
          <h2 className="font-semibold text-red-800 dark:text-red-200">Unable to load matches</h2>
          <p className="mt-1 text-sm text-red-700 dark:text-red-300">{state.message}</p>
          <button
            className="mt-4 min-h-11 rounded-lg bg-red-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-600 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-950"
            onClick={() => setRetryCount((count) => count + 1)}
            type="button"
          >
            Try again
          </button>
        </div>
      </section>
    );
  }

  return (
    <section>
      {state.matches.length > 0 ? (
        <MatchRail matches={state.matches} />
      ) : (
        <div className="mt-8 rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <h2 className="font-semibold text-slate-950 dark:text-white">
            {state.seasonName ? 'No published matches yet' : 'No league seasons yet'}
          </h2>
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
            {state.seasonName
              ? `${state.seasonName} does not have any published fixtures or results.`
              : 'No league seasons are available yet.'}
          </p>
        </div>
      )}
    </section>
  );
}
