import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { TeamBadge } from '../../components/TeamBadge';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';
import type { MatchScoringState, ScoringInnings } from './liveMatchTypes';
import {
  formatOvers,
  getBattingScorecard,
  getBowlingScorecard,
  getCommentary,
  getCurrentBatters,
  getExtras,
  getFallOfWickets,
  getInningsTotals,
  getTeamName,
  type BatterScore,
  type BowlerScore,
} from './publicLiveScoreUtils';

const commentaryPreviewSize = 10;

function formatMatchDate(value: string | null) {
  if (!value) return 'Date to be confirmed';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Date to be confirmed';
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

function getResultMessage(state: MatchScoringState) {
  if (state.match.status !== 'completed') return null;
  if (state.match.result_type === 'tie') return 'Match tied';
  if (state.match.result_type === 'no_result') return 'No result';
  if (state.match.result_type === 'win' && state.match.winner_season_team_id) {
    const winnerTeamName = getTeamName(state, state.match.winner_season_team_id);
    const winnerInnings = state.innings.find(
      (innings) => innings.batting_season_team_id === state.match.winner_season_team_id
        || getTeamName(state, innings.batting_season_team_id) === winnerTeamName,
    );
    const otherInnings = state.innings.find(
      (innings) => innings !== winnerInnings,
    );

    if (winnerInnings && otherInnings) {
      const winnerTotals = getInningsTotals(winnerInnings);
      const otherTotals = getInningsTotals(otherInnings);
      if (winnerInnings.innings_number === 1) {
        const runMargin = Math.max(winnerTotals.runs - otherTotals.runs, 0);
        return `${winnerTeamName} won by ${runMargin} run${runMargin === 1 ? '' : 's'}`;
      }

      const lineupSize = state.lineups.filter(
        (player) => player.season_team_id === state.match.winner_season_team_id,
      ).length;
      const wicketMargin = Math.max(lineupSize - 1 - winnerTotals.wickets, 0);
      return wicketMargin > 0
        ? `${winnerTeamName} won by ${wicketMargin} wicket${wicketMargin === 1 ? '' : 's'}`
        : `${winnerTeamName} won`;
    }

    return `${winnerTeamName} won`;
  }
  return 'Match completed';
}

function getMatchSituation(state: MatchScoringState, innings: ScoringInnings) {
  const totals = getInningsTotals(innings);

  if (state.match.status === 'completed') return getResultMessage(state) ?? 'Match completed';
  if (innings.target_score !== null) {
    const runsNeeded = Math.max(innings.target_score - totals.runs, 0);
    const ballsRemaining = Math.max(innings.legal_balls_limit - totals.legalBalls, 0);
    if (runsNeeded === 0) return 'Target reached';
    return `${runsNeeded} run${runsNeeded === 1 ? '' : 's'} needed from ${ballsRemaining} ball${ballsRemaining === 1 ? '' : 's'}`;
  }
  return `${getTeamName(state, innings.batting_season_team_id)} batting`;
}

function ScoreHero({
  state,
  innings,
  currentBatters,
  currentBowler,
}: {
  state: MatchScoringState;
  innings: ScoringInnings;
  currentBatters: BatterScore[];
  currentBowler: BowlerScore | null;
}) {
  const totals = getInningsTotals(innings);
  const battingTeamName = getTeamName(state, innings.batting_season_team_id);
  const bowlingTeamName = getTeamName(state, innings.bowling_season_team_id);
  const bowlingTeamInnings = state.innings.find(
    (teamInnings) => teamInnings.batting_season_team_id === innings.bowling_season_team_id,
  );
  const bowlingTeamTotals = bowlingTeamInnings ? getInningsTotals(bowlingTeamInnings) : null;
  const isLive = state.match.status === 'live';

  return (
    <section className="overflow-hidden rounded-2xl bg-gradient-to-br from-slate-950 via-slate-900 to-emerald-950 text-white shadow-xl shadow-slate-950/15">
      <header className="flex flex-wrap items-center justify-between gap-2 border-b border-white/10 px-4 py-3 sm:px-6">
        <span className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-black uppercase tracking-[0.14em] ${isLive ? 'bg-emerald-400 text-emerald-950' : 'bg-white/10 text-slate-200'}`}>
          {isLive ? <span aria-hidden="true" className="h-2 w-2 animate-pulse rounded-full bg-emerald-950" /> : null}
          {isLive ? 'Live' : 'Result'}
        </span>
        <span className="text-xs font-semibold text-slate-300">{state.match.venue || 'Venue to be confirmed'}</span>
      </header>

      <div className="grid items-center gap-5 px-4 py-6 sm:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] sm:px-6 sm:py-8">
        <div className="flex min-w-0 items-center justify-center gap-3 text-center sm:justify-start sm:text-left">
          <TeamBadge teamName={battingTeamName} />
          <div className="min-w-0">
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-emerald-300">Batting</p>
            <h1 className="truncate text-lg font-black sm:text-2xl">{battingTeamName}</h1>
            <p className="mt-1 text-xl font-black sm:text-2xl">{totals.runs}/{totals.wickets}</p>
            <p className="text-[11px] font-semibold text-slate-400">{formatOvers(totals.legalBalls, innings.balls_per_over)} overs</p>
          </div>
        </div>

        <div aria-live="polite" className="text-center">
          <p className="text-5xl font-black tracking-[-0.06em] sm:text-6xl">{totals.runs}/{totals.wickets}</p>
          <p className="mt-1 text-sm font-bold text-slate-300">
            {formatOvers(totals.legalBalls, innings.balls_per_over)} overs
          </p>
          <p className="mt-2 text-sm font-extrabold text-emerald-300">{getMatchSituation(state, innings)}</p>
        </div>

        <div className="flex min-w-0 items-center justify-center gap-3 text-center sm:flex-row-reverse sm:justify-start sm:text-right">
          <TeamBadge teamName={bowlingTeamName} />
          <div className="min-w-0">
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-slate-400">Bowling</p>
            <h2 className="truncate text-lg font-black sm:text-2xl">{bowlingTeamName}</h2>
            {bowlingTeamTotals ? <>
              <p className="mt-1 text-xl font-black sm:text-2xl">{bowlingTeamTotals.runs}/{bowlingTeamTotals.wickets}</p>
              <p className="text-[11px] font-semibold text-slate-400">{formatOvers(bowlingTeamTotals.legalBalls, bowlingTeamInnings?.balls_per_over ?? innings.balls_per_over)} overs</p>
            </> : <p className="mt-1 text-xs font-semibold text-slate-400">Yet to bat</p>}
          </div>
        </div>
      </div>

      <div className="grid border-t border-white/10 bg-black/15 md:grid-cols-[1.4fr_1fr]">
        <div className="border-b border-white/10 px-4 py-4 md:border-b-0 md:border-r sm:px-6">
          <div className="grid grid-cols-[minmax(0,1fr)_2rem_2rem_2rem_2rem_3rem] gap-1 text-[10px] font-bold uppercase tracking-wide text-slate-400 sm:grid-cols-[minmax(0,1fr)_2.5rem_2.5rem_2.5rem_2.5rem_3.5rem]">
            <span>{isLive ? 'Current' : 'Not out'} batter{currentBatters.length === 1 ? '' : 's'}</span>
            <span className="text-right">R</span>
            <span className="text-right">B</span>
            <span className="text-right">4s</span>
            <span className="text-right">6s</span>
            <span className="text-right">SR</span>
          </div>
          {currentBatters.length > 0 ? currentBatters.map((batter) => (
            <div className="mt-2 grid grid-cols-[minmax(0,1fr)_2rem_2rem_2rem_2rem_3rem] items-center gap-1 text-sm sm:grid-cols-[minmax(0,1fr)_2.5rem_2.5rem_2.5rem_2.5rem_3.5rem]" key={batter.playerId}>
              <strong className="flex min-w-0 items-center gap-2 truncate">
                {isLive && batter.isCurrent ? <span aria-label="On strike" className="h-2 w-2 shrink-0 rounded-full bg-emerald-400" /> : null}
                <span className="truncate">{batter.name}{batter.isCaptain ? ' (c)' : ''}</span>
              </strong>
              <strong className="text-right">{batter.runs}</strong>
              <span className="text-right text-slate-300">{batter.balls}</span>
              <span className="text-right text-slate-300">{batter.fours}</span>
              <span className="text-right text-slate-300">{batter.sixes}</span>
              <span className="text-right text-slate-300">{batter.strikeRate.toFixed(1)}</span>
            </div>
          )) : <p className="mt-2 text-sm font-semibold text-slate-300">Innings complete</p>}
        </div>

        <div className="px-4 py-4 sm:px-6">
          <div className="grid grid-cols-[minmax(0,1fr)_2rem_2rem_2rem_2rem_3rem] gap-1 text-[10px] font-bold uppercase tracking-wide text-slate-400 sm:grid-cols-[minmax(0,1fr)_2.5rem_2.5rem_2.5rem_2.5rem_3.5rem]">
            <span>{isLive ? 'Bowler' : 'Last bowler'}</span>
            <span className="text-right">O</span>
            <span className="text-right">M</span>
            <span className="text-right">R</span>
            <span className="text-right">W</span>
            <span className="text-right">Econ</span>
          </div>
          {currentBowler ? (
            <div className="mt-2 grid grid-cols-[minmax(0,1fr)_2rem_2rem_2rem_2rem_3rem] items-center gap-1 text-sm sm:grid-cols-[minmax(0,1fr)_2.5rem_2.5rem_2.5rem_2.5rem_3.5rem]">
              <strong className="truncate">{currentBowler.name}</strong>
              <span className="text-right">{formatOvers(currentBowler.legalBalls, innings.balls_per_over)}</span>
              <span className="text-right text-slate-300">{currentBowler.maidens}</span>
              <span className="text-right text-slate-300">{currentBowler.runs}</span>
              <strong className="text-right text-rose-400">{currentBowler.wickets}</strong>
              <span className="text-right text-slate-300">{currentBowler.economy.toFixed(2)}</span>
            </div>
          ) : <p className="mt-2 text-sm font-semibold text-slate-300">Bowler not assigned</p>}
        </div>
      </div>
    </section>
  );
}

function CommentaryPanel({ state, innings }: { state: MatchScoringState; innings: ScoringInnings }) {
  const [showAll, setShowAll] = useState(false);
  const commentary = getCommentary(state, innings);
  const visibleCommentary = showAll ? commentary : commentary.slice(0, commentaryPreviewSize);
  const overGroups = [...visibleCommentary.reduce((groups, item) => {
    const group = groups.get(item.overNumber) ?? [];
    group.push(item);
    groups.set(item.overNumber, group);
    return groups;
  }, new Map<number, typeof visibleCommentary>())].map(([overNumber, items]) => ({
    overNumber,
    items,
    runs: items.reduce((total, item) => total + item.runs, 0),
  }));

  return (
    <section className="min-w-0 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <header className="border-b border-slate-200 px-4 py-4 dark:border-slate-800 sm:px-5">
        <h2 className="text-sm font-black uppercase tracking-[0.12em] text-slate-950 dark:text-white">Ball-by-ball</h2>
      </header>
      {overGroups.length > 0 ? (
        <div className="space-y-1 p-1.5">
          {overGroups.map((group) => (
            <section className="overflow-hidden rounded-xl border border-slate-200 dark:border-slate-800" key={group.overNumber}>
              <header className="flex items-center justify-between gap-3 bg-slate-50 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.12em] text-slate-500 dark:bg-slate-950 dark:text-slate-400">
                <span>Over {group.overNumber}</span>
                <span>{group.runs} run{group.runs === 1 ? '' : 's'}</span>
              </header>
              <ol className="divide-y divide-slate-100 dark:divide-slate-800">
                {group.items.map((item) => (
                  <li className={`grid grid-cols-[2.6rem_2.25rem_minmax(0,1fr)] items-start gap-2 px-3 py-2.5 text-sm ${item.id === commentary[0]?.id ? 'bg-emerald-50/70 dark:bg-emerald-950/20' : ''}`} key={item.id}>
                    <strong className="pt-1 text-slate-950 dark:text-white">{item.ballLabel}</strong>
                    <span className={`flex h-8 w-8 items-center justify-center rounded-full text-[11px] font-black ${item.tone === 'wicket' ? 'bg-rose-500 text-white' : item.tone === 'boundary' ? 'bg-amber-400 text-amber-950' : 'bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-100'}`}>
                      {item.badge}
                    </span>
                    <span className="pt-1 leading-5 text-slate-700 dark:text-slate-200">{item.description}</span>
                  </li>
                ))}
              </ol>
            </section>
          ))}
        </div>
      ) : (
        <p className="px-5 py-8 text-sm text-slate-500 dark:text-slate-400">Commentary will appear when scoring begins.</p>
      )}
      {commentary.length > commentaryPreviewSize ? (
        <button className="min-h-11 w-full border-t border-slate-200 px-4 text-sm font-bold text-emerald-700 hover:bg-slate-50 dark:border-slate-800 dark:text-emerald-300 dark:hover:bg-slate-800" onClick={() => setShowAll((current) => !current)} type="button">
          {showAll ? 'Show latest only' : `View all ${commentary.length} deliveries`}
        </button>
      ) : null}
    </section>
  );
}

function ScorecardPanel({
  state,
  innings,
}: {
  state: MatchScoringState;
  innings: ScoringInnings;
}) {
  const batting = getBattingScorecard(state, innings);
  const bowling = getBowlingScorecard(state, innings);
  const extras = getExtras(innings);
  const totals = getInningsTotals(innings);
  const wickets = getFallOfWickets(state, innings);

  return (
    <section className="min-w-0 space-y-3">
      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <header className="border-b border-slate-200 px-4 py-4 dark:border-slate-800">
          <h2 className="text-sm font-black uppercase tracking-[0.12em] text-slate-950 dark:text-white">Scorecard</h2>
          <p className="mt-1 text-xs font-semibold text-slate-500 dark:text-slate-400">{getTeamName(state, innings.batting_season_team_id)}</p>
        </header>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[24rem] text-left text-xs">
            <thead className="bg-slate-50 text-[10px] font-black uppercase tracking-wide text-slate-500 dark:bg-slate-950 dark:text-slate-400">
              <tr><th className="px-4 py-2">Batter</th><th className="px-2 py-2 text-right">R</th><th className="px-2 py-2 text-right">B</th><th className="px-2 py-2 text-right">4s</th><th className="px-2 py-2 text-right">6s</th><th className="px-4 py-2 text-right">SR</th></tr>
            </thead>
            <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
              {batting.map((batter) => (
                <tr key={batter.playerId}>
                  <td className="px-4 py-2.5"><strong className="text-slate-950 dark:text-white">{batter.name}{batter.isCaptain ? ' (c)' : ''}</strong><span className="mt-0.5 block text-[11px] text-slate-500 dark:text-slate-400">{batter.dismissal}</span></td>
                  <td className="px-2 py-2.5 text-right font-black text-slate-950 dark:text-white">{batter.runs}</td>
                  <td className="px-2 py-2.5 text-right text-slate-600 dark:text-slate-300">{batter.balls}</td>
                  <td className="px-2 py-2.5 text-right text-slate-600 dark:text-slate-300">{batter.fours}</td>
                  <td className="px-2 py-2.5 text-right text-slate-600 dark:text-slate-300">{batter.sixes}</td>
                  <td className="px-4 py-2.5 text-right text-slate-600 dark:text-slate-300">{batter.strikeRate.toFixed(1)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4 border-t border-slate-200 px-4 py-3 text-sm dark:border-slate-800">
          <span className="font-semibold text-slate-600 dark:text-slate-300">Extras <small className="ml-1 text-slate-400">({extras.wides}wd, {extras.noBalls}nb, {extras.deadBalls}db)</small></span>
          <strong>{extras.total}</strong>
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4 bg-emerald-50 px-4 py-3 text-sm text-emerald-900 dark:bg-emerald-950/40 dark:text-emerald-200">
          <strong className="uppercase tracking-wide">Total</strong>
          <strong>{totals.runs}/{totals.wickets} ({formatOvers(totals.legalBalls, innings.balls_per_over)} overs)</strong>
        </div>
      </div>

      <div className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <header className="border-b border-slate-200 px-4 py-3 dark:border-slate-800"><h3 className="text-xs font-black uppercase tracking-[0.12em]">Bowling</h3></header>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[24rem] text-xs">
            <thead className="bg-slate-50 text-[10px] font-black uppercase text-slate-500 dark:bg-slate-950 dark:text-slate-400"><tr><th className="px-4 py-2 text-left">Bowler</th><th className="px-2 py-2 text-right">O</th><th className="px-2 py-2 text-right">M</th><th className="px-2 py-2 text-right">R</th><th className="px-2 py-2 text-right">W</th><th className="px-4 py-2 text-right">Econ</th></tr></thead>
            <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
              {bowling.map((bowler) => <tr key={bowler.playerId}><td className="px-4 py-2.5 text-left font-bold">{bowler.name}</td><td className="px-2 py-2.5 text-right">{formatOvers(bowler.legalBalls, innings.balls_per_over)}</td><td className="px-2 py-2.5 text-right">{bowler.maidens}</td><td className="px-2 py-2.5 text-right">{bowler.runs}</td><td className="px-2 py-2.5 text-right font-black text-rose-600 dark:text-rose-400">{bowler.wickets}</td><td className="px-4 py-2.5 text-right">{bowler.economy.toFixed(2)}</td></tr>)}
            </tbody>
          </table>
        </div>
      </div>

      <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h3 className="text-xs font-black uppercase tracking-[0.12em]">Fall of wickets</h3>
        {wickets.length > 0 ? (
          <ol className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-1">
            {wickets.map((wicket) => <li className="rounded-xl bg-slate-50 px-3 py-2 text-xs dark:bg-slate-950" key={`${wicket.wicketNumber}-${wicket.playerName}`}><strong>{wicket.wicketNumber}-{wicket.score}</strong><span className="ml-2 text-slate-500 dark:text-slate-400">({wicket.over} ov)</span><span className="mt-1 block font-semibold text-slate-700 dark:text-slate-200">{wicket.playerName}</span></li>)}
          </ol>
        ) : <p className="mt-2 text-sm text-slate-500 dark:text-slate-400">No wickets have fallen.</p>}
      </div>
    </section>
  );
}

function ScheduledMatch({ state }: { state: MatchScoringState }) {
  return (
    <section className="overflow-hidden rounded-2xl bg-slate-950 p-6 text-center text-white shadow-xl sm:p-10">
      <span className="rounded-full bg-white/10 px-3 py-1 text-xs font-black uppercase tracking-[0.14em] text-slate-200">Upcoming</span>
      <div className="mt-6 grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-3">
        <div className="flex min-w-0 flex-col items-center gap-2"><TeamBadge teamName={state.match.home_team_name} /><strong className="break-words">{state.match.home_team_name}</strong></div>
        <span className="rounded-full bg-emerald-400 px-3 py-2 text-xs font-black text-emerald-950">VS</span>
        <div className="flex min-w-0 flex-col items-center gap-2"><TeamBadge teamName={state.match.away_team_name} /><strong className="break-words">{state.match.away_team_name}</strong></div>
      </div>
      <p className="mt-6 text-sm font-semibold text-slate-300">Live scoring will appear here when the match begins.</p>
    </section>
  );
}

export function PublicLiveScorePage() {
  const { matchId } = useParams();
  const [state, setState] = useState<MatchScoringState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedInningsNumber, setSelectedInningsNumber] = useState<number | null>(null);

  const loadState = useCallback(async () => {
    if (!matchId || !supabase || !isSupabaseConfigured) {
      setError('Live scores are not configured.');
      setLoading(false);
      return;
    }

    const { data, error: loadError } = await supabase.rpc('get_match_scoring_state', {
      target_match_id: matchId,
    });

    if (loadError) {
      setError('Unable to load this match right now.');
      setLoading(false);
      return;
    }

    const nextState = data as MatchScoringState | null;
    if (!nextState?.match) {
      setError('Detailed scoring is not available for this match.');
      setLoading(false);
      return;
    }

    setState(nextState);
    setError(null);
    setLoading(false);
  }, [matchId]);

  useEffect(() => {
    void loadState();
  }, [loadState]);

  const inningsKey = state?.innings.map((innings) => innings.id).join(',') ?? '';

  useEffect(() => {
    if (!supabase || !matchId || state?.match.status !== 'live') return undefined;
    const client = supabase;
    const inningsIds = inningsKey ? inningsKey.split(',') : [];
    const reload = () => { void loadState(); };
    const channel = client
      .channel(`public-live-score-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, reload)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_innings', filter: `match_id=eq.${matchId}` }, reload);

    inningsIds.forEach((inningsId) => {
      channel
        .on('postgres_changes', { event: '*', schema: 'public', table: 'match_over_assignments', filter: `innings_id=eq.${inningsId}` }, reload)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'match_batting_turns', filter: `innings_id=eq.${inningsId}` }, reload)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'match_deliveries', filter: `innings_id=eq.${inningsId}` }, reload);
    });

    channel.subscribe();
    return () => { void client.removeChannel(channel); };
  }, [inningsKey, loadState, matchId, state?.match.status]);

  const displayInnings = useMemo(() => {
    if (!state?.innings.length) return null;
    return state.innings.find((innings) => innings.status === 'live')
      ?? [...state.innings].sort((first, second) => second.innings_number - first.innings_number)[0];
  }, [state]);
  const scorecardInnings = state?.innings.find(
    (innings) => innings.innings_number === selectedInningsNumber,
  ) ?? displayInnings;
  const battingScorecard = state && displayInnings
    ? getBattingScorecard(state, displayInnings)
    : [];
  const currentBatters = state && displayInnings
    ? getCurrentBatters(state, displayInnings, battingScorecard)
    : [];
  const bowlingScorecard = state && displayInnings
    ? getBowlingScorecard(state, displayInnings)
    : [];
  const lastBowlerId = displayInnings?.overs
    .flatMap((over) => over.deliveries)
    .sort((first, second) => first.delivery_sequence - second.delivery_sequence)
    .at(-1)?.bowler_season_roster_id
    ?? displayInnings?.overs.at(-1)?.bowler_season_roster_id;
  const currentBowler = bowlingScorecard.find((bowler) => bowler.playerId === lastBowlerId) ?? null;

  if (loading) {
    return <section aria-busy="true" className="mx-auto max-w-6xl"><p className="text-sm text-slate-600 dark:text-slate-300" role="status">Loading match score…</p><div aria-hidden="true" className="mt-4 h-80 animate-pulse rounded-2xl bg-slate-200 dark:bg-slate-800" /></section>;
  }

  if (!state) {
    return <section className="surface-card mx-auto max-w-2xl p-5"><h1 className="text-xl font-black text-slate-950 dark:text-white">Score unavailable</h1><p className="mt-2 text-sm text-slate-600 dark:text-slate-300">{error ?? 'This match could not be loaded.'}</p><Link className="mt-4 inline-flex min-h-11 items-center rounded-lg bg-brand-500 px-4 text-sm font-bold text-slate-950" to="/matches">Back to matches</Link></section>;
  }

  return (
    <section className="mx-auto max-w-6xl space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <Link className="text-xs font-bold text-slate-500 hover:text-emerald-700 dark:text-slate-400 dark:hover:text-emerald-300" to="/matches">← Matches</Link>
          <p className="mt-2 text-xs font-bold uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">{formatMatchDate(state.match.match_date)}</p>
        </div>
        {state.match.status === 'live' ? <span className="inline-flex items-center gap-2 text-xs font-bold text-emerald-700 dark:text-emerald-300"><span className="h-2 w-2 animate-pulse rounded-full bg-emerald-500" />Updating live</span> : <span className="text-xs font-bold text-slate-500 dark:text-slate-400">Fetched from match records</span>}
      </div>

      {error ? <p className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-900 dark:bg-amber-950/30 dark:text-amber-200" role="alert">{error}</p> : null}

      {displayInnings ? (
        <>
          <ScoreHero currentBatters={currentBatters} currentBowler={currentBowler} innings={displayInnings} state={state} />

          {state.innings.length > 1 ? (
            <nav aria-label="Innings scorecards" className="flex gap-2 overflow-x-auto pb-1">
              {state.innings.map((innings) => {
                const totals = getInningsTotals(innings);
                const isSelected = scorecardInnings?.id === innings.id;
                return <button aria-current={isSelected ? 'page' : undefined} className={`min-h-11 shrink-0 rounded-xl border px-4 text-left text-xs font-bold ${isSelected ? 'border-emerald-500 bg-emerald-500 text-emerald-950' : 'border-slate-200 bg-white text-slate-700 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-200'}`} key={innings.id} onClick={() => setSelectedInningsNumber(innings.innings_number)} type="button"><span className="block">{getTeamName(state, innings.batting_season_team_id)}</span><span className="mt-0.5 block text-[11px] opacity-75">{totals.runs}/{totals.wickets} ({formatOvers(totals.legalBalls, innings.balls_per_over)})</span></button>;
              })}
            </nav>
          ) : null}

          <div className="grid min-w-0 items-start gap-4 lg:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.85fr)]">
            <CommentaryPanel innings={displayInnings} state={state} />
            {scorecardInnings ? <ScorecardPanel innings={scorecardInnings} state={state} /> : null}
          </div>
        </>
      ) : <ScheduledMatch state={state} />}
    </section>
  );
}
