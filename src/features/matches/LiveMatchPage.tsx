import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { DeliveryStrip } from '../../components/DeliveryStrip';
import { ScoreButton } from '../../components/ScoreButton';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';
import type {
  DeliveryType,
  DismissalType,
  MatchScoringState,
  RecordedDismissalType,
  ScoringDelivery,
  ScoringInnings,
  ScoringLineup,
  ScoringOver,
} from './liveMatchTypes';

const LEGAL_RUNS = [0, 1, 2, 4, 6] as const;
const NO_BALL_BATTER_RUNS = [0, 1, 2, 4, 6] as const;
const DISMISSAL_OPTIONS: { value: DismissalType; label: string }[] = [
  { value: 'bowled', label: 'Bowled' },
  { value: 'caught', label: 'Caught' },
  { value: 'stumped', label: 'Stumped' },
  { value: 'hit_wicket', label: 'Hit Wicket' },
  { value: 'hit_out_of_field', label: 'Hit out of Field' },
];

type OverForm = {
  bowlerId: string;
  wicketkeeperId: string;
};

type EditDeliveryForm = {
  id: string;
  strikerId: string;
  deliveryType: DeliveryType;
  batterRuns: string;
  extraRuns: string;
  isWicket: boolean;
  dismissalType: RecordedDismissalType;
  fielderId: string;
};

type SelectOption = { value: string; label: string };

function SelectField({
  label,
  value,
  options,
  onChange,
  disabled = false,
}: {
  label: string;
  value: string;
  options: SelectOption[];
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <label className="text-xs font-bold uppercase tracking-wide text-slate-600 dark:text-slate-300">
      {label}
      <select
        className="form-select mt-1 normal-case tracking-normal"
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        <option value="">Choose {label.toLowerCase()}</option>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}

function getOverLegalBalls(over: ScoringOver) {
  return over.deliveries.filter((delivery) => delivery.delivery_type === 'legal').length;
}

function getInningsScore(innings: ScoringInnings) {
  return innings.overs.reduce(
    (total, over) => total + over.deliveries.reduce((overTotal, delivery) => overTotal + delivery.batter_runs + delivery.extra_runs, 0),
    0,
  );
}

function getInningsLegalBalls(innings: ScoringInnings) {
  return innings.overs.reduce((total, over) => total + getOverLegalBalls(over), 0);
}

function formatOvers(legalBalls: number, ballsPerOver: number) {
  return `${Math.floor(legalBalls / ballsPerOver)}.${legalBalls % ballsPerOver}`;
}

function getTeamAbbreviation(teamName: string) {
  const parts = teamName.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return parts.map((part) => part[0] ?? '').join('').slice(0, 2).toUpperCase();
}

function getBowlerOverCount(innings: ScoringInnings, seasonRosterId: string) {
  return innings.overs.filter((over) => over.bowler_season_roster_id === seasonRosterId).length;
}

function getDismissedIds(innings: ScoringInnings) {
  return new Set(
    innings.overs.flatMap((over) => over.deliveries)
      .map((delivery) => delivery.dismissed_season_roster_id)
      .filter((playerId): playerId is string => Boolean(playerId)),
  );
}

function getTeamPlayers(lineups: ScoringLineup[], seasonTeamId: string) {
  return lineups.filter((lineup) => lineup.season_team_id === seasonTeamId);
}

function MatchHeading({ state }: { state: MatchScoringState }) {
  return (
    <header className="score-match-header">
      <div className="score-match-header__top">
        <div className="min-w-0">
          <p className="score-live-label"><span aria-hidden="true" /> LIVE · {state.match.home_team_name.toUpperCase()} VS {state.match.away_team_name.toUpperCase()}</p>
        </div>
        <span className="score-format">
          {state.match.status}
        </span>
      </div>
    </header>
  );
}

function ScoreSummary({
  innings,
  homeInnings,
  awayInnings,
  homeTeamName,
  awayTeamName,
}: {
  innings: ScoringInnings;
  homeInnings: ScoringInnings | null;
  awayInnings: ScoringInnings | null;
  homeTeamName: string;
  awayTeamName: string;
}) {
  const score = getInningsScore(innings);
  const legalBalls = getInningsLegalBalls(innings);
  const runsRequired = innings.target_score === null ? null : Math.max(innings.target_score - score, 0);
  const ballsRemaining = Math.max(innings.legal_balls_limit - legalBalls, 0);
  const targetReached = innings.target_score !== null && runsRequired === 0;
  const teamScores = [
    { innings: homeInnings, name: homeTeamName },
    { innings: awayInnings, name: awayTeamName },
  ];

  return (
    <section className="score-board sticky top-2 z-10">
      <div className="score-board__scores">
        {teamScores.map((team) => {
          const teamScore = team.innings ? getInningsScore(team.innings) : 0;
          const teamWickets = team.innings ? [...getDismissedIds(team.innings)].length : 0;
          const teamBalls = team.innings ? getInningsLegalBalls(team.innings) : 0;
          const isActive = team.innings?.id === innings.id;
          return (
            <div className={`score-board__score ${isActive ? 'score-board__score--active' : ''}`} key={team.name}>
              <span>{getTeamAbbreviation(team.name)}</span>
              <strong>{team.innings ? `${teamScore}/${teamWickets}` : '—/—'}</strong>
              <small>{team.innings ? `${formatOvers(teamBalls, team.innings.balls_per_over)} Overs` : 'Not started'}</small>
            </div>
          );
        })}
      </div>
      <div className="score-board__target">
        <span>{targetReached ? 'Status' : 'Runs required'}</span>
        <strong>{targetReached ? 'Target reached' : runsRequired !== null ? `${runsRequired} run${runsRequired === 1 ? '' : 's'} from ${ballsRemaining} ball${ballsRemaining === 1 ? '' : 's'}` : '—'}</strong>
      </div>
    </section>
  );
}

function SectionLabel({ children }: { children: string }) {
  return <h4 className="mb-2 text-[10px] font-black uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">{children}</h4>;
}

export function LiveMatchPage() {
  const { matchId } = useParams();
  const navigate = useNavigate();
  const [state, setState] = useState<MatchScoringState | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [firstBattingTeamId, setFirstBattingTeamId] = useState('');
  const [historicalEntry, setHistoricalEntry] = useState(false);
  const [playerOfMatchId, setPlayerOfMatchId] = useState('');
  const [overForm, setOverForm] = useState<OverForm>({
    bowlerId: '',
    wicketkeeperId: '',
  });
  const [nextBatterId, setNextBatterId] = useState('');
  const [changingFlexibleBatter, setChangingFlexibleBatter] = useState(false);
  const [changingBowler, setChangingBowler] = useState(false);
  const [dismissalType, setDismissalType] = useState<DismissalType>('bowled');
  const [fielderId, setFielderId] = useState('');
  const [scoringPrompt, setScoringPrompt] = useState<'no_ball' | 'wide' | 'dead_ball' | 'wicket' | null>(null);
  const [stumpingWicketkeeperId, setStumpingWicketkeeperId] = useState('');
  const [editingDelivery, setEditingDelivery] = useState<EditDeliveryForm | null>(null);

  const loadState = useCallback(async () => {
    if (!matchId || !supabase || !isSupabaseConfigured) {
      setError('Supabase is not configured.');
      setLoading(false);
      return;
    }

    const { data, error: loadError } = await supabase.rpc('get_match_scoring_state', {
      target_match_id: matchId,
    });

    if (loadError) {
      setError(loadError.message);
      setLoading(false);
      return;
    }

    setState(data as MatchScoringState | null);
    setLoading(false);
  }, [matchId]);

  useEffect(() => {
    void loadState();
  }, [loadState]);

  useEffect(() => {
    if (!supabase || !matchId) return undefined;
    const client = supabase;
    const channel = client
      .channel(`live-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'matches', filter: `id=eq.${matchId}` }, () => { void loadState(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_innings', filter: `match_id=eq.${matchId}` }, () => { void loadState(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_over_assignments' }, () => { void loadState(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_batting_turns' }, () => { void loadState(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_deliveries' }, () => { void loadState(); })
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [loadState, matchId]);

  useEffect(() => {
    if (!state) return;
    setFirstBattingTeamId((current) => current || state.match.home_season_team_id);
    setPlayerOfMatchId((current) => current || state.lineups[0]?.id || '');
    if (state.match.status === 'scheduled') {
      setHistoricalEntry(state.match.historical_batting_exception);
    }
  }, [state]);

  const activeInnings = useMemo(
    () => state?.innings.find((innings) => innings.status === 'live') ?? null,
    [state],
  );

  const currentOver = useMemo(() => {
    if (!activeInnings) return null;
    return activeInnings.overs.find((over) => !over.confirmed_at) ?? null;
  }, [activeInnings]);

  const nextOverNumber = useMemo(() => {
    if (!activeInnings) return 1;
    const highestOver = activeInnings.overs.at(-1)?.over_number ?? 0;
    return currentOver?.over_number ?? highestOver + 1;
  }, [activeInnings, currentOver]);

  const currentContextKey = activeInnings
    ? `${activeInnings.id}:${currentOver?.id ?? nextOverNumber}`
    : '';

  useEffect(() => {
    if (!state || !activeInnings || !currentContextKey) return;

    const bowlingPlayers = getTeamPlayers(state.lineups, activeInnings.bowling_season_team_id);
    const availableBowlers = bowlingPlayers.filter(
      (player) => currentOver?.bowler_season_roster_id === player.season_roster_id
        || getBowlerOverCount(activeInnings, player.season_roster_id) < activeInnings.max_overs_per_player,
    );
    const selectedBowlerId = currentOver?.bowler_season_roster_id ?? availableBowlers[0]?.season_roster_id ?? '';
    setOverForm({
      bowlerId: selectedBowlerId,
      wicketkeeperId: currentOver?.wicketkeeper_season_roster_id ?? selectedBowlerId,
    });
    setFielderId(currentOver?.wicketkeeper_season_roster_id ?? '');
    setDismissalType('bowled');
    setEditingDelivery(null);
  }, [activeInnings, currentContextKey, currentOver, state]);

  async function runAction(functionName: string, args: Record<string, unknown>) {
    if (!supabase) return null;
    setSaving(true);
    setError(null);
    const { data, error: actionError } = await supabase.rpc(functionName, args);
    if (actionError) {
      setError(actionError.message);
      setSaving(false);
      return null;
    }
    await loadState();
    setSaving(false);
    return data;
  }

  async function startMatch() {
    if (!matchId || !firstBattingTeamId) {
      setError('Choose the first batting team.');
      return;
    }
    if (historicalEntry && !state?.match.historical_batting_exception) {
      const exceptionResult = await runAction('set_match_historical_batting_exception', {
        target_match_id: matchId,
        enabled: true,
      });
      if (exceptionResult !== true) return;
    }
    await runAction('start_match', {
      target_match_id: matchId,
      first_batting_season_team_id: firstBattingTeamId,
    });
  }

  async function assignOver() {
    if (!activeInnings || !overForm.bowlerId) {
      setError('Choose the bowler.');
      return;
    }
    const result = await runAction('set_match_over_assignment', {
      target_innings_id: activeInnings.id,
      target_over_number: nextOverNumber,
      target_bowler_season_roster_id: overForm.bowlerId,
      target_wicketkeeper_season_roster_id: overForm.wicketkeeperId,
    });
    if (result) setChangingBowler(false);
  }

  async function selectBatter() {
    if (!activeInnings || !nextBatterId) {
      setError('Choose the next batsman.');
      return;
    }

    const result = await runAction('select_match_batter', {
      target_innings_id: activeInnings.id,
      target_batter_season_roster_id: nextBatterId,
    });

    if (result) {
      setNextBatterId('');
      setChangingFlexibleBatter(false);
    }
  }

  async function recordDelivery(
    deliveryType: DeliveryType,
    batterRuns = 0,
    extraRuns = 0,
    wicket = false,
    dismissalOverride?: DismissalType,
    wicketkeeperOverride?: string,
  ) {
    if (!activeInnings || !currentOver || !activeBattingTurn) {
      setError('Choose the next batsman before recording the delivery.');
      return;
    }

    if (getOverLegalBalls(currentOver) >= activeInnings.balls_per_over) {
      setError('Review and confirm the completed over before continuing.');
      return;
    }

    if (inningsCanEnd) {
      setError('Complete the innings before recording another delivery.');
      return;
    }

    const appliedDismissalType = dismissalOverride ?? dismissalType;
    const appliedWicketkeeperId = wicketkeeperOverride ?? overForm.wicketkeeperId;
    await runAction('record_match_delivery', {
      target_over_assignment_id: currentOver.id,
      target_striker_season_roster_id: activeBattingTurn.batter_season_roster_id,
      target_non_striker_season_roster_id: null,
      target_delivery_type: deliveryType,
      target_batter_runs: batterRuns,
      target_extra_runs: extraRuns,
      target_is_wicket: wicket,
      target_dismissed_season_roster_id: wicket ? activeBattingTurn.batter_season_roster_id : null,
      target_dismissal_type: wicket ? appliedDismissalType : null,
      target_fielder_season_roster_id: wicket && appliedDismissalType === 'stumped'
        ? appliedWicketkeeperId
        : wicket && appliedDismissalType === 'caught'
          ? fielderId || null
          : null,
    });
  }

  async function recordStumping(deliveryType: DeliveryType, batterRuns = 0, extraRuns = 0) {
    if (!stumpingWicketkeeperId || !currentOver) {
      setError('Choose the wicketkeeper for this stumping.');
      return;
    }
    if (stumpingWicketkeeperId === currentOver.bowler_season_roster_id) {
      setError('Choose a wicketkeeper other than the bowler.');
      return;
    }
    const keeperChanged = stumpingWicketkeeperId !== currentOver.wicketkeeper_season_roster_id;
    if (keeperChanged) {
      const result = await runAction('change_current_over_wicketkeeper', {
        target_over_assignment_id: currentOver.id,
        target_wicketkeeper_season_roster_id: stumpingWicketkeeperId,
      });
      if (!result) return;
    }
    setOverForm((current) => ({ ...current, wicketkeeperId: stumpingWicketkeeperId }));
    setScoringPrompt(null);
    await recordDelivery(deliveryType, batterRuns, extraRuns, true, 'stumped', stumpingWicketkeeperId);
  }

  function openScoringPrompt(prompt: 'no_ball' | 'wide' | 'dead_ball' | 'wicket') {
    if (prompt === 'wicket') {
      setDismissalType('bowled');
      setFielderId('');
      setStumpingWicketkeeperId(defaultStumpingWicketkeeperId);
    }
    setScoringPrompt(prompt);
  }

  async function completeInnings() {
    if (!activeInnings) return;
    await runAction('complete_match_innings', { target_innings_id: activeInnings.id });
  }

  async function confirmOver() {
    if (!currentOver) return;
    if (!window.confirm(`Confirm and lock over ${currentOver.over_number}? You cannot edit it after confirmation.`)) return;
    await runAction('confirm_match_over', { target_over_assignment_id: currentOver.id });
  }

  async function finalizeMatch() {
    if (!matchId || !playerOfMatchId) {
      setError('Choose the player of the match.');
      return;
    }
    await runAction('finalize_match', {
      target_match_id: matchId,
      player_of_match_lineup_id: playerOfMatchId,
    });
  }

  async function markNoResult() {
    if (!matchId || !window.confirm('Mark this match as no result?')) return;
    await runAction('mark_match_no_result', { target_match_id: matchId });
  }

  async function recordForfeit(forfeitingTeamId: string) {
    if (!matchId) return;
    const forfeitingTeamName = forfeitingTeamId === state?.match.home_season_team_id ? state.match.home_team_name : state?.match.away_team_name;
    if (!forfeitingTeamName || !window.confirm(`${forfeitingTeamName} cannot field the minimum five players. Record this match as a forfeit?`)) return;
    const reason = window.prompt('Forfeit reason', `${forfeitingTeamName} could not field the minimum five players.`)?.trim();
    if (!reason) return;
    await runAction('record_match_forfeit', {
      target_match_id: matchId,
      forfeiting_season_team_id: forfeitingTeamId,
      target_reason: reason,
    });
  }

  function beginEdit(delivery: ScoringDelivery) {
    setEditingDelivery({
      id: delivery.id,
      strikerId: delivery.striker_season_roster_id,
      deliveryType: delivery.delivery_type,
      batterRuns: String(delivery.batter_runs),
      extraRuns: String(delivery.extra_runs),
      isWicket: delivery.is_wicket,
      dismissalType: delivery.dismissal_type ?? 'bowled',
      fielderId: delivery.fielder_season_roster_id ?? '',
    });
  }

  async function saveDeliveryEdit() {
    if (!editingDelivery) return;
    const result = await runAction('update_current_over_delivery', {
      target_delivery_id: editingDelivery.id,
      target_striker_season_roster_id: editingDelivery.strikerId,
      target_non_striker_season_roster_id: null,
      target_delivery_type: editingDelivery.deliveryType,
      target_batter_runs: Number(editingDelivery.batterRuns) || 0,
      target_extra_runs: Number(editingDelivery.extraRuns) || 0,
      target_is_wicket: editingDelivery.isWicket,
      target_dismissed_season_roster_id: editingDelivery.isWicket ? editingDelivery.strikerId : null,
      target_dismissal_type: editingDelivery.isWicket ? editingDelivery.dismissalType : null,
      target_fielder_season_roster_id: editingDelivery.isWicket
        ? editingDelivery.dismissalType === 'stumped'
          ? overForm.wicketkeeperId
          : editingDelivery.dismissalType === 'caught'
            ? editingDelivery.fielderId || null
            : null
        : null,
    });
    if (result) setEditingDelivery(null);
  }

  async function deleteDelivery(deliveryId: string) {
    if (!window.confirm('Delete this delivery from the current over?')) return;
    await runAction('delete_current_over_delivery', { target_delivery_id: deliveryId });
  }

  if (loading) return <p className="text-sm text-slate-600 dark:text-slate-300">Loading live match…</p>;
  if (!state) {
    return (
      <section className="surface-card mx-auto max-w-3xl space-y-2 p-4">
        <h2 className="text-base font-bold text-slate-950 dark:text-white">Unable to load this match</h2>
        <p className="text-sm text-slate-600 dark:text-slate-300">The scorer could not load the live match state.</p>
        {error ? <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{error}</p> : null}
        <Link className="inline-flex text-sm font-bold text-brand-700 hover:underline dark:text-brand-300" to="/matches">Return to matches</Link>
      </section>
    );
  }

  const homePlayers = getTeamPlayers(state.lineups, state.match.home_season_team_id);
  const awayPlayers = getTeamPlayers(state.lineups, state.match.away_season_team_id);
  const isScheduled = state.match.status === 'scheduled';
  const isCompleted = state.match.status === 'completed';
  const firstInnings = state.innings.find((innings) => innings.innings_number === 1);
  const secondInnings = state.innings.find((innings) => innings.innings_number === 2);
  const homeInnings = state.innings.find((innings) => innings.batting_season_team_id === state.match.home_season_team_id) ?? null;
  const awayInnings = state.innings.find((innings) => innings.batting_season_team_id === state.match.away_season_team_id) ?? null;
  const currentBattingPlayers = activeInnings ? getTeamPlayers(state.lineups, activeInnings.batting_season_team_id) : [];
  const currentBowlingPlayers = activeInnings ? getTeamPlayers(state.lineups, activeInnings.bowling_season_team_id) : [];
  const dismissed = activeInnings ? getDismissedIds(activeInnings) : new Set<string>();
  const availableBatters = currentBattingPlayers.filter((player) => !dismissed.has(player.season_roster_id));
  const battingTurns = activeInnings?.batting_turns ?? [];
  const activeBattingTurn = battingTurns.find((turn) => turn.status === 'active') ?? null;
  const initialTurnPlayerIds = new Set(
    battingTurns
      .filter((turn) => turn.phase === 'initial')
      .map((turn) => turn.batter_season_roster_id),
  );
  const initialPhaseComplete = Boolean(activeInnings && (
    state.match.historical_batting_exception
      ? initialTurnPlayerIds.size >= Math.max(currentBattingPlayers.length - 1, 0)
      : currentBattingPlayers.every((player) => (
        battingTurns.some((turn) => (
          turn.phase === 'initial'
          && turn.batter_season_roster_id === player.season_roster_id
          && turn.status === 'ended'
          && (turn.end_reason === 'six_balls' || turn.end_reason === 'dismissed')
        ))
      ))
  ));
  const battingPhase = initialPhaseComplete ? 'flexible' : 'initial';
  const eligibleBatters = availableBatters.filter((player) => (
    battingPhase === 'flexible'
    || !initialTurnPlayerIds.has(player.season_roster_id)
    || (changingFlexibleBatter
      && activeBattingTurn?.phase === 'initial'
      && activeBattingTurn.legal_balls_faced === 0
      && activeBattingTurn.batter_season_roster_id === player.season_roster_id)
  ));
  const availableBowlers = currentBowlingPlayers.filter(
    (player) => currentOver?.bowler_season_roster_id === player.season_roster_id
      || (activeInnings
        ? getBowlerOverCount(activeInnings, player.season_roster_id) < activeInnings.max_overs_per_player
        : false),
  );
  const currentBowlerId = currentOver?.bowler_season_roster_id ?? overForm.bowlerId;
  const keeperOptions = currentBowlingPlayers.filter((player) => player.season_roster_id !== currentBowlerId);
  const defaultStumpingWicketkeeperId = keeperOptions.some(
    (player) => player.season_roster_id === currentOver?.wicketkeeper_season_roster_id,
  )
    ? currentOver?.wicketkeeper_season_roster_id ?? ''
    : keeperOptions[0]?.season_roster_id ?? '';
  const currentOverComplete = Boolean(
    activeInnings
    && currentOver
    && getOverLegalBalls(currentOver) >= activeInnings.balls_per_over,
  );
  const inningsCanEnd = activeInnings
    ? getInningsLegalBalls(activeInnings) >= activeInnings.legal_balls_limit
      || availableBatters.length === 0
      || (activeInnings.target_score !== null && getInningsScore(activeInnings) >= activeInnings.target_score)
    : false;
  const bothInningsCompleted = Boolean(firstInnings?.status === 'completed' && secondInnings?.status === 'completed');
  const needsNextBatter = Boolean(activeInnings && !activeBattingTurn && !inningsCanEnd && !currentOverComplete);
  const batterPromptOpen = needsNextBatter || changingFlexibleBatter;
  const canChangeBatter = Boolean(
    activeBattingTurn
    && (activeBattingTurn.phase === 'flexible' || activeBattingTurn.legal_balls_faced === 0),
  );
  const canRecordWicket = Boolean(activeBattingTurn);

  return (
    <section className="score-page mx-auto max-w-3xl space-y-4">
      <div className="flex items-center justify-between gap-3">
        <Link className="score-back text-xs font-bold" to="/matches">
          ← Matches
        </Link>
        {isCompleted ? <button className="score-back text-xs font-bold" onClick={() => navigate('/standings')} type="button">View standings</button> : null}
      </div>

      <MatchHeading state={state} />
      {state.match.status === 'live' ? <Link className="inline-flex text-xs font-bold text-brand-700 hover:underline dark:text-brand-300" to={`/matches/${state.match.id}/live/bulk`}>Open bulk entry</Link> : null}
      {error ? <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{error}</p> : null}

      {isScheduled ? (
        <section className="surface-card p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 className="text-base font-bold text-slate-950 dark:text-white">Start match</h3>
              <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">
                {homePlayers.length} vs {awayPlayers.length} players · {Math.min(homePlayers.length, awayPlayers.length)} overs per innings
              </p>
            </div>
            <ScoreButton disabled={saving} onClick={() => void startMatch()} tone="accent">Start</ScoreButton>
          </div>
          <div className="mt-3">
            <SelectField
              label="First batting team"
              onChange={setFirstBattingTeamId}
              options={[
                { value: state.match.home_season_team_id, label: state.match.home_team_name },
                { value: state.match.away_season_team_id, label: state.match.away_team_name },
              ]}
              value={firstBattingTeamId}
            />
          </div>
          <label className="mt-4 flex min-h-11 items-start gap-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-900 dark:bg-amber-950/30 dark:text-amber-100">
            <input
              checked={historicalEntry}
              className="mt-1 h-4 w-4 accent-brand-500"
              disabled={saving || state.match.historical_batting_exception}
              onChange={(event) => setHistoricalEntry(event.target.checked)}
              type="checkbox"
            />
            <span>
              <span className="block font-bold">Historical entry: allow incomplete batting turns</span>
              <span className="mt-1 block text-xs text-amber-800 dark:text-amber-200">
                Use only when the recorded match did not give every lineup player a batting turn. This setting cannot be changed after the match starts.
              </span>
            </span>
          </label>
          <div className="mt-4 border-t border-slate-200 pt-4 dark:border-slate-800">
            <h4 className="text-sm font-bold text-slate-950 dark:text-white">Record forfeit instead</h4>
            <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">No lineup or first batting team is required. The selected team will be recorded as forfeiting.</p>
            <div className="mt-3 grid gap-2 sm:grid-cols-2">
              <ScoreButton disabled={saving} onClick={() => void recordForfeit(state.match.home_season_team_id)} tone="danger">{state.match.home_team_name} forfeits</ScoreButton>
              <ScoreButton disabled={saving} onClick={() => void recordForfeit(state.match.away_season_team_id)} tone="danger">{state.match.away_team_name} forfeits</ScoreButton>
            </div>
          </div>
        </section>
      ) : null}

      {activeInnings ? (
        <ScoreSummary
          awayInnings={awayInnings}
          awayTeamName={state.match.away_team_name}
          homeInnings={homeInnings}
          homeTeamName={state.match.home_team_name}
          innings={activeInnings}
        />
      ) : null}

      {currentOver ? <DeliveryStrip onDeliveryClick={beginEdit} over={currentOver} /> : null}

      {activeInnings && currentOver ? (
        <section className="score-over-card surface-card p-4">
          <div className="score-person-line">
            <span className="score-person-line__label">Bowler</span>
            <strong className="score-person-line__name">{currentOver.bowler_name}</strong>
            {currentOver.deliveries.length === 0 && !changingBowler ? (
              <ScoreButton
                className="min-h-9 shrink-0 px-3 py-1.5 text-xs"
                disabled={saving}
                onClick={() => setChangingBowler(true)}
              >
                Change bowler
              </ScoreButton>
            ) : null}
          </div>

          {currentOver.deliveries.length === 0 && changingBowler ? (
            <div className="mt-4 rounded-xl border border-brand-200 bg-brand-50 p-3 dark:border-brand-900 dark:bg-brand-950/30">
              <SelectField
                label="New bowler"
                onChange={(value) => setOverForm({ bowlerId: value, wicketkeeperId: value })}
                options={availableBowlers.map((player) => ({ value: player.season_roster_id, label: player.player_name }))}
                value={overForm.bowlerId}
              />
              <div className="mt-3 flex flex-wrap gap-2">
                <ScoreButton disabled={saving || !overForm.bowlerId} onClick={() => void assignOver()} tone="accent">
                  Save bowler
                </ScoreButton>
                <ScoreButton disabled={saving} onClick={() => setChangingBowler(false)}>
                  Cancel
                </ScoreButton>
              </div>
            </div>
           ) : null}
            {activeBattingTurn ? (
            <div className="score-person-line mt-4">
              <span className="score-person-line__label">Batsman</span>
              <strong className="score-person-line__name min-w-0 truncate">{activeBattingTurn.batter_name}</strong>
              <span className="score-batter-line__balls">{activeBattingTurn.legal_balls_faced} balls</span>
              {canChangeBatter ? (
                <ScoreButton
                  className="min-h-9 shrink-0 px-3 py-1.5 text-xs"
                  disabled={saving || currentOverComplete}
                  onClick={() => {
                    setNextBatterId(activeBattingTurn.batter_season_roster_id);
                    setChangingFlexibleBatter(true);
                  }}
                >
                  Change batsman
                </ScoreButton>
              ) : null}
            </div>
          ) : null}

          <div className="mt-4">
            <div>
              {/*<p className="score-keypad-label">Interactive scoring keypad</p>*/}
              <SectionLabel>Runs off bat</SectionLabel>
              <div className="score-over-balls">
                {LEGAL_RUNS.map((runs) => (
                  <ScoreButton className={runs === 4 ? 'score-run-button--four' : runs === 6 ? 'score-run-button--six' : ''} disabled={saving || inningsCanEnd || batterPromptOpen || currentOverComplete} key={runs} onClick={() => void recordDelivery('legal', runs)}>
                    {runs}
                  </ScoreButton>
                ))}
              </div>
            </div>
          </div>

          <div className="score-event-buttons mt-4">
            <ScoreButton className="score-event-button--no-ball" disabled={saving || inningsCanEnd || batterPromptOpen || currentOverComplete} onClick={() => openScoringPrompt('no_ball')}>NB</ScoreButton>
            <ScoreButton className="score-event-button--neutral" disabled={saving || inningsCanEnd || batterPromptOpen || currentOverComplete} onClick={() => void recordDelivery('wide', 0, 1)}>WD</ScoreButton>
            <ScoreButton className="score-event-button--neutral" disabled={saving || inningsCanEnd || batterPromptOpen || currentOverComplete} onClick={() => void recordDelivery('dead_ball', 0, 1)}>DB</ScoreButton>
            <ScoreButton disabled={saving || inningsCanEnd || batterPromptOpen || !canRecordWicket || currentOverComplete} onClick={() => openScoringPrompt('wicket')} tone="danger">Wk</ScoreButton>
          </div>

          {currentOverComplete ? (
            <div className="mt-4 rounded-xl border border-brand-200 bg-brand-50 p-3 dark:border-brand-900 dark:bg-brand-950/30">
              <p className="text-sm font-bold text-slate-950 dark:text-white">Over {currentOver.over_number} is complete</p>
              <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">Review or edit deliveries from the score summary before locking this over.</p>
              <ScoreButton className="mt-3 w-full" disabled={saving} onClick={() => void confirmOver()} tone="accent">
                Confirm and lock over
              </ScoreButton>
            </div>
          ) : null}
        </section>
      ) : null}

      {activeInnings && !currentOver && !inningsCanEnd && activeInnings.status === 'live' ? (
        <section className="surface-card p-4">
          <h3 className="text-base font-bold text-slate-950 dark:text-white">Set over {nextOverNumber}</h3>
          <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">The current batsman continues across overs.</p>
          <div className="mt-3">
            <SelectField
              label="Bowler"
              onChange={(value) => setOverForm({ bowlerId: value, wicketkeeperId: value })}
              options={availableBowlers.map((player) => ({ value: player.season_roster_id, label: player.player_name }))}
              value={overForm.bowlerId}
            />
          </div>
          <ScoreButton className="mt-3" disabled={saving} onClick={() => void assignOver()} tone="accent">Assign over</ScoreButton>
        </section>
      ) : null}

      {activeInnings && inningsCanEnd && (!currentOver || !currentOverComplete) ? (
        <section className="surface-card p-4">
          <h3 className="text-base font-bold text-slate-950 dark:text-white">End innings</h3>
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
            {activeInnings.target_score !== null && getInningsScore(activeInnings) >= activeInnings.target_score
              ? 'The target has been reached.'
              : getInningsLegalBalls(activeInnings) >= activeInnings.legal_balls_limit
                ? 'The legal-ball limit has been reached.'
                : 'No eligible batters remain.'}
          </p>
          <ScoreButton className="mt-3" disabled={saving} onClick={() => void completeInnings()} tone="accent">Complete innings</ScoreButton>
        </section>
      ) : null}

      {state.match.status === 'live' && bothInningsCompleted ? (
        <section className="surface-card p-4">
          <h3 className="text-base font-bold text-slate-950 dark:text-white">Finalize match</h3>
          <div className="mt-3 grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
            <SelectField
              label="Player of the match"
              onChange={setPlayerOfMatchId}
              options={state.lineups.map((lineup) => ({ value: lineup.id, label: lineup.player_name }))}
              value={playerOfMatchId}
            />
            <ScoreButton disabled={saving} onClick={() => void finalizeMatch()} tone="accent">Finalize result</ScoreButton>
          </div>
          <ScoreButton className="mt-3" disabled={saving} onClick={() => void markNoResult()} tone="danger">Mark no result</ScoreButton>
        </section>
      ) : null}

      {isCompleted ? (
        <section className="surface-card p-4">
          <h3 className="text-base font-bold text-slate-950 dark:text-white">Match completed</h3>
          <p className="mt-1 text-sm font-medium text-slate-600 dark:text-slate-300">
            {state.match.result_type === 'no_result'
              ? 'No result — both teams receive one point.'
              : state.match.result_type === 'forfeit'
                ? `Winner by forfeit: ${state.match.winner_season_team_id === state.match.home_season_team_id ? state.match.home_team_name : state.match.away_team_name}`
              : state.match.result_type === 'tie'
                ? 'Tie — both teams receive one point.'
                : `Winner: ${state.match.winner_season_team_id === state.match.home_season_team_id ? state.match.home_team_name : state.match.away_team_name}`}
          </p>
        </section>
      ) : null}

      {batterPromptOpen && activeInnings && eligibleBatters.length > 0 ? (
        <div className="fixed inset-0 z-30 flex items-end justify-center bg-slate-950/50 p-3 sm:items-center">
          <section aria-labelledby="batter-prompt-title" aria-modal="true" className="w-full max-w-md rounded-2xl bg-white p-4 shadow-2xl dark:bg-slate-900 sm:p-5" role="dialog">
            <p className="text-[10px] font-black uppercase tracking-[0.14em] text-brand-600 dark:text-brand-400">
              {battingPhase === 'flexible' ? 'Preserved balls' : 'Six-ball batting turns'}
            </p>
            <h3 className="mt-1 text-lg font-bold text-slate-950 dark:text-white" id="batter-prompt-title">
              {changingFlexibleBatter ? 'Change batsman' : battingTurns.length === 0 ? 'Choose first batsman' : 'Choose next batsman'}
            </h3>
            <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
              {battingPhase === 'flexible'
                ? 'Every player has completed a turn or been dismissed. Choose any not-out batsman.'
                : 'Choose a not-out player who has not received their initial six-ball turn.'}
            </p>
            <div className="mt-4">
              <SelectField
                label="Next batsman"
                onChange={setNextBatterId}
                options={eligibleBatters.map((player) => ({ value: player.season_roster_id, label: player.player_name }))}
                value={nextBatterId}
              />
            </div>
            <div className="mt-4 flex gap-2">
              {changingFlexibleBatter ? (
                <ScoreButton
                  className="flex-1"
                  disabled={saving}
                  onClick={() => {
                    setChangingFlexibleBatter(false);
                    setNextBatterId('');
                  }}
                >
                  Cancel
                </ScoreButton>
              ) : null}
              <ScoreButton className="flex-1" disabled={saving || !nextBatterId} onClick={() => void selectBatter()} tone="accent">
                Continue scoring
              </ScoreButton>
            </div>
          </section>
        </div>
      ) : null}

      {scoringPrompt && currentOver ? (
        <div className="fixed inset-0 z-30 flex items-end justify-center bg-slate-950/50 p-3 sm:items-center">
          <section aria-labelledby="scoring-prompt-title" aria-modal="true" className="w-full max-w-md rounded-2xl bg-white p-4 shadow-2xl dark:bg-slate-900 sm:p-5" role="dialog">
            <p className="text-[10px] font-black uppercase tracking-[0.14em] text-brand-600 dark:text-brand-400">Scoring prompt</p>
            <h3 className="mt-1 text-lg font-bold text-slate-950 dark:text-white" id="scoring-prompt-title">
              {scoringPrompt === 'no_ball' ? 'No ball' : scoringPrompt === 'wide' ? 'Wide' : scoringPrompt === 'dead_ball' ? 'Dead ball' : 'Wicket'}
            </h3>
            {scoringPrompt === 'no_ball' ? (
              <>
                <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">Select runs scored off the bat. One no-ball extra run will be added.</p>
                <div className="score-event-buttons mt-4">
                  {NO_BALL_BATTER_RUNS.map((runs) => (
                    <ScoreButton className={runs === 4 ? 'score-run-button--four' : runs === 6 ? 'score-run-button--six' : ''} disabled={saving} key={runs} onClick={() => { setScoringPrompt(null); void recordDelivery('no_ball', runs, 1); }}>{runs}</ScoreButton>
                  ))}
                </div>
              </>
            ) : null}
            {scoringPrompt === 'wide' || scoringPrompt === 'dead_ball' ? (
              <>
                <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">One extra run will be added.</p>
                <ScoreButton className="mt-4 w-full" disabled={saving} onClick={() => { const type = scoringPrompt; setScoringPrompt(null); void recordDelivery(type, 0, 1); }} tone="accent">Record +1</ScoreButton>
              </>
            ) : null}
            {scoringPrompt === 'wicket' ? (
              <>
                <div className="mt-4 grid gap-3">
                  <SelectField label="Dismissal" onChange={(value) => setDismissalType(value as DismissalType)} options={DISMISSAL_OPTIONS} value={dismissalType} />
                  {dismissalType === 'caught' ? <SelectField label="Fielder" onChange={setFielderId} options={currentBowlingPlayers.map((player) => ({ value: player.season_roster_id, label: player.player_name }))} value={fielderId} /> : null}
                  {dismissalType === 'stumped' ? <SelectField label="Wicketkeeper" onChange={setStumpingWicketkeeperId} options={keeperOptions.map((player) => ({ value: player.season_roster_id, label: player.player_name }))} value={stumpingWicketkeeperId} /> : null}
                </div>
                <ScoreButton className="mt-4 w-full" disabled={saving || (dismissalType === 'stumped' && !stumpingWicketkeeperId)} onClick={() => dismissalType === 'stumped' ? void recordStumping('legal') : (() => { setScoringPrompt(null); void recordDelivery('legal', 0, 0, true); })()} tone="danger">Record wicket</ScoreButton>
              </>
            ) : null}
            <ScoreButton className="mt-2 w-full" disabled={saving} onClick={() => setScoringPrompt(null)}>Cancel</ScoreButton>
          </section>
        </div>
      ) : null}

      {editingDelivery ? (
        <div className="fixed inset-0 z-20 flex items-end justify-center bg-slate-950/50 p-3 sm:items-center">
          <section className="w-full max-w-md rounded-2xl bg-white p-4 shadow-2xl dark:bg-slate-900 sm:p-5">
            <div className="flex items-center justify-between gap-3">
              <h3 className="text-base font-bold text-slate-950 dark:text-white">Edit delivery</h3>
              <button className="text-xs font-bold text-slate-500 hover:text-slate-950 dark:text-slate-400 dark:hover:text-white" onClick={() => setEditingDelivery(null)} type="button">Close</button>
            </div>
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <SelectField
                label="Delivery type"
                onChange={(value) => setEditingDelivery((current) => current ? {
                  ...current,
                  deliveryType: value as DeliveryType,
                  extraRuns: value === 'dead_ball' && current.deliveryType !== 'dead_ball' ? '1' : current.extraRuns,
                } : current)}
                options={[
                  { value: 'legal', label: 'Legal ball' },
                  { value: 'wide', label: 'Wide' },
                  { value: 'no_ball', label: 'No-ball' },
                  { value: 'dead_ball', label: 'Dead ball' },
                ]}
                value={editingDelivery.deliveryType}
              />
              <label className="text-xs font-bold uppercase tracking-wide text-slate-600 dark:text-slate-300">Batter runs<input className="mt-1 block min-h-10 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm font-normal normal-case tracking-normal dark:border-slate-700 dark:bg-slate-950 dark:text-white" min="0" onChange={(event) => setEditingDelivery((current) => current ? { ...current, batterRuns: event.target.value } : current)} type="number" value={editingDelivery.batterRuns} /></label>
              <label className="text-xs font-bold uppercase tracking-wide text-slate-600 dark:text-slate-300">Extra runs<input className="mt-1 block min-h-10 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm font-normal normal-case tracking-normal dark:border-slate-700 dark:bg-slate-950 dark:text-white" min="0" onChange={(event) => setEditingDelivery((current) => current ? { ...current, extraRuns: event.target.value } : current)} type="number" value={editingDelivery.extraRuns} /></label>
              <label className="flex min-h-10 items-center gap-2 text-sm font-semibold text-slate-700 dark:text-slate-200"><input checked={editingDelivery.isWicket} onChange={(event) => setEditingDelivery((current) => current ? { ...current, isWicket: event.target.checked } : current)} type="checkbox" /> Wicket</label>
            </div>
            {editingDelivery.isWicket ? (
              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                <SelectField label="Dismissal" onChange={(value) => setEditingDelivery((current) => current ? { ...current, dismissalType: value as DismissalType } : current)} options={DISMISSAL_OPTIONS} value={editingDelivery.dismissalType} />
                {editingDelivery.dismissalType === 'caught' ? (
                  <SelectField label="Fielder" onChange={(value) => setEditingDelivery((current) => current ? { ...current, fielderId: value } : current)} options={currentBowlingPlayers.map((player) => ({ value: player.season_roster_id, label: player.player_name }))} value={editingDelivery.fielderId} />
                ) : <div />}
              </div>
            ) : null}
            <div className="mt-4 flex flex-wrap gap-2">
              <ScoreButton disabled={saving} onClick={() => void saveDeliveryEdit()} tone="accent">Save delivery</ScoreButton>
              <ScoreButton disabled={saving} onClick={() => { void deleteDelivery(editingDelivery.id).then(() => setEditingDelivery(null)); }} tone="danger">Delete delivery</ScoreButton>
              <ScoreButton disabled={saving} onClick={() => setEditingDelivery(null)}>Cancel</ScoreButton>
            </div>
          </section>
        </div>
      ) : null}
    </section>
  );
}
