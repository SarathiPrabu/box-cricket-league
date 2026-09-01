import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ScoreButton } from '../../components/ScoreButton';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';
import type { DeliveryType, MatchScoringState } from './liveMatchTypes';

type Entry = { batterId: string; bowlerId: string; type: DeliveryType; batterRuns: string; extraRuns: string };
const blank = (): Entry => ({ batterId: '', bowlerId: '', type: 'legal', batterRuns: '0', extraRuns: '0' });

export function BulkEntryPage() {
  const { matchId } = useParams();
  const [state, setState] = useState<MatchScoringState | null>(null);
  const [entries, setEntries] = useState<Entry[]>([blank()]);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadState = useCallback(async () => {
    if (!matchId || !supabase || !isSupabaseConfigured) return;
    const { data, error: loadError } = await supabase.rpc('get_match_scoring_state', { target_match_id: matchId });
    if (loadError) setError(loadError.message);
    else setState(data as MatchScoringState);
  }, [matchId]);
  useEffect(() => { void loadState(); }, [loadState]);

  const innings = state?.innings.find((item) => item.status === 'live') ?? null;
  const over = innings?.overs.find((item) => !item.confirmed_at) ?? null;
  const batters = useMemo(() => state?.lineups.filter((item) => item.season_team_id === innings?.batting_season_team_id) ?? [], [innings, state]);
  const bowlers = useMemo(() => (state?.lineups.filter((item) => item.season_team_id === innings?.bowling_season_team_id) ?? []).filter((player) => {
    if (!innings) return false;
    const overs = innings.overs.filter((item) => item.bowler_season_roster_id === player.season_roster_id).length;
    return player.season_roster_id === over?.bowler_season_roster_id || overs < innings.max_overs_per_player;
  }), [innings, over, state]);

  function update(index: number, values: Partial<Entry>) {
    setEntries((current) => current.map((entry, itemIndex) => itemIndex === index ? { ...entry, ...values } : entry));
  }

  async function saveAll() {
    if (!supabase || !innings || !over) { setError('Start the match and assign the current over first.'); return; }
    const valid = entries.filter((entry) => entry.batterId && entry.bowlerId);
    if (!valid.length) { setError('Add at least one complete delivery row.'); return; }
    const bowlerId = valid[0].bowlerId;
    if (valid.some((entry) => entry.bowlerId !== bowlerId)) { setError('Use one bowler for all rows in the current over.'); return; }
    setSaving(true); setError(null); setMessage(null);
    if (over.deliveries.length === 0 && over.bowler_season_roster_id !== bowlerId) {
      const assignment = await supabase.rpc('set_match_over_assignment', {
        target_innings_id: innings.id,
        target_over_number: over.over_number,
        target_bowler_season_roster_id: bowlerId,
        target_wicketkeeper_season_roster_id: bowlerId,
      });
      if (assignment.error) { setError(assignment.error.message); setSaving(false); return; }
    }
    for (const [index, entry] of valid.entries()) {
      const turn = await supabase.rpc('select_match_batter', { target_innings_id: innings.id, target_batter_season_roster_id: entry.batterId });
      if (turn.error && !turn.error.message.toLowerCase().includes('already')) { setError(`Row ${index + 1}: ${turn.error.message}`); setSaving(false); return; }
      const result = await supabase.rpc('record_match_delivery', {
        target_over_assignment_id: over.id,
        target_striker_season_roster_id: entry.batterId,
        target_non_striker_season_roster_id: null,
        target_delivery_type: entry.type,
        target_batter_runs: Number(entry.batterRuns) || 0,
        target_extra_runs: Number(entry.extraRuns) || 0,
        target_is_wicket: false,
        target_dismissed_season_roster_id: null,
        target_dismissal_type: null,
        target_fielder_season_roster_id: null,
      });
      if (result.error) { setError(`Row ${index + 1}: ${result.error.message}`); setSaving(false); return; }
    }
    setEntries([blank()]); setMessage(`${valid.length} deliver${valid.length === 1 ? 'y' : 'ies'} saved.`); setSaving(false); await loadState();
  }

  return <section className="score-page mx-auto max-w-4xl space-y-4">
    <div className="flex items-center justify-between"><Link className="score-back text-xs font-bold" to={matchId ? `/matches/${matchId}/live` : '/matches'}>← Live scorer</Link><span className="score-format">Bulk entry</span></div>
    <section className="surface-card p-4"><h1 className="text-lg font-bold text-slate-950 dark:text-white">Bulk innings entry</h1><p className="mt-1 text-sm text-slate-600 dark:text-slate-300">Add delivery rows, then post them in order. The current over and batting-turn rules still apply.</p></section>
    {error ? <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700" role="alert">{error}</p> : null}
    {message ? <p className="rounded-lg border border-brand-200 bg-brand-50 p-3 text-sm text-brand-800" role="status">{message}</p> : null}
    {!innings || !over ? <section className="surface-card p-4 text-sm text-slate-600 dark:text-slate-300">Start the match and assign an active over before entering deliveries.</section> : <section className="surface-card overflow-hidden p-4">
      <div className="mb-3 flex items-center justify-between"><h2 className="font-bold text-slate-950 dark:text-white">Over {over.over_number}</h2><span className="text-xs text-slate-500">{over.deliveries.length} recorded</span></div>
      <div className="mb-2 hidden gap-2 px-3 text-[10px] font-black uppercase tracking-[0.12em] text-slate-500 dark:text-slate-400 sm:grid sm:grid-cols-[1.2fr_1.2fr_.9fr_.7fr_.7fr_auto]">
        <span>Batsman</span><span>Bowler</span><span>Delivery</span><span>Bat runs</span><span>Extras</span><span>Actions</span>
      </div>
      <div className="space-y-3">{entries.map((entry, index) => <div className="grid gap-2 rounded-xl border border-slate-200 p-3 dark:border-slate-700 sm:grid-cols-[1.2fr_1.2fr_.9fr_.7fr_.7fr_auto]" key={index}>
        <select className="form-select" value={entry.batterId} onChange={(event) => update(index, { batterId: event.target.value })}><option value="">Batsman</option>{batters.map((player) => <option key={player.season_roster_id} value={player.season_roster_id}>{player.player_name}</option>)}</select>
        <select className="form-select" value={entry.bowlerId} onChange={(event) => update(index, { bowlerId: event.target.value })}><option value="">Bowler</option>{bowlers.map((player) => <option key={player.season_roster_id} value={player.season_roster_id}>{player.player_name}</option>)}</select>
        <select className="form-select" value={entry.type} onChange={(event) => update(index, { type: event.target.value as DeliveryType })}><option value="legal">Legal</option><option value="wide">Wide</option><option value="no_ball">No-ball</option><option value="dead_ball">Dead ball</option></select>
        <input className="form-select" min="0" type="number" aria-label="Batter runs" value={entry.batterRuns} onChange={(event) => update(index, { batterRuns: event.target.value })} />
        <input className="form-select" min="0" type="number" aria-label="Extra runs" value={entry.extraRuns} onChange={(event) => update(index, { extraRuns: event.target.value })} />
        <button className="min-h-11 px-2 text-sm font-bold text-red-600" type="button" onClick={() => setEntries((current) => current.filter((_, itemIndex) => itemIndex !== index))}>Remove</button>
      </div>)}</div>
      <div className="mt-4 flex flex-wrap gap-2"><ScoreButton disabled={saving} onClick={() => setEntries((current) => [...current, blank()])}>+ Add delivery</ScoreButton><ScoreButton disabled={saving} onClick={() => void saveAll()} tone="accent">{saving ? 'Posting…' : 'Post deliveries'}</ScoreButton></div>
    </section>}
  </section>;
}
