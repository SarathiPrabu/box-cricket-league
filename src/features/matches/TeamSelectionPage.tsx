import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useLocation, useParams, useSearchParams } from 'react-router-dom';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

type SelectionPlayer = {
  season_roster_id: string;
  player_id: string;
  display_name: string;
  selected: boolean;
};

type SelectionTeam = {
  season_team_id: string;
  team_name: string;
  editable: boolean;
  selected_roster_ids: string[];
  captain_roster_id: string | null;
  players: SelectionPlayer[];
};

type SelectionState = {
  match: {
    id: string;
    season_id: string;
    status: 'draft' | 'scheduled' | 'live' | 'completed' | 'cancelled';
    match_date: string | null;
    venue: string | null;
    home_season_team_id: string;
    away_season_team_id: string;
  };
  min_players: number;
  max_players: number;
  is_admin: boolean;
  editable_season_team_id: string | null;
  teams: SelectionTeam[];
};

type PageState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; selection: SelectionState };

function formatMatchDate(value: string | null) {
  if (!value) return 'Time to be confirmed';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}

export function TeamSelectionPage() {
  const { matchId } = useParams();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const matchesSearch = `${searchParams.toString() ? `?${searchParams.toString()}` : ''}${location.hash}`;
  const [state, setState] = useState<PageState>({ status: 'loading' });
  const [selectedByTeam, setSelectedByTeam] = useState<Record<string, string[]>>({});
  const [captainByTeam, setCaptainByTeam] = useState<Record<string, string | null>>({});
  const [activeTeamId, setActiveTeamId] = useState<string | null>(null);
  const [savingTeamId, setSavingTeamId] = useState<string | null>(null);
  const [captainPromptTeam, setCaptainPromptTeam] = useState<SelectionTeam | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const loadState = useCallback(async () => {
    if (!matchId || !supabase || !isSupabaseConfigured) {
      setState({ status: 'error', message: 'Supabase is not configured.' });
      return;
    }

    setState({ status: 'loading' });
    setError(null);

    const { data, error: loadError } = await supabase.rpc('get_match_team_selection_state', {
      target_match_id: matchId,
    });

    if (loadError) {
      setState({ status: 'error', message: loadError.message });
      return;
    }

    const selection = data as SelectionState;
    setState({ status: 'ready', selection });
    setSelectedByTeam(Object.fromEntries(selection.teams.map((team) => [team.season_team_id, team.selected_roster_ids])));
    setCaptainByTeam(Object.fromEntries(selection.teams.map((team) => [team.season_team_id, team.captain_roster_id])));
    setActiveTeamId((current) => current ?? selection.editable_season_team_id ?? selection.teams[0]?.season_team_id ?? null);
  }, [matchId]);

  useEffect(() => {
    void loadState();
  }, [loadState]);

  const activeTeam = useMemo(() => {
    if (state.status !== 'ready') return null;
    return state.selection.teams.find((team) => team.season_team_id === activeTeamId) ?? state.selection.teams[0] ?? null;
  }, [activeTeamId, state]);

  function togglePlayer(teamId: string, rosterId: string) {
    setSelectedByTeam((current) => {
      const selected = current[teamId] ?? [];
      return {
        ...current,
        [teamId]: selected.includes(rosterId)
          ? selected.filter((id) => id !== rosterId)
          : [...selected, rosterId],
      };
    });
    setSuccess(null);
  }

  function promptForCaptain(team: SelectionTeam) {
    if (!supabase || !matchId || state.status !== 'ready') return;

    const selected = selectedByTeam[team.season_team_id] ?? [];
    if (selected.length < state.selection.min_players || selected.length > state.selection.max_players) {
      setError(`Select between ${state.selection.min_players} and ${state.selection.max_players} players for ${team.team_name}.`);
      return;
    }

    setError(null);
    setSuccess(null);
    setCaptainPromptTeam(team);
  }

  async function saveTeamSelection(team: SelectionTeam) {
    if (!supabase || !matchId || state.status !== 'ready') return;

    const selected = selectedByTeam[team.season_team_id] ?? [];
    const captainRosterId = captainByTeam[team.season_team_id];
    if (!captainRosterId || !selected.includes(captainRosterId)) {
      setError('Choose one of the selected players as captain.');
      return;
    }

    setSavingTeamId(team.season_team_id);
    setError(null);
    setSuccess(null);

    const { error: saveError } = await supabase.rpc('save_match_team_lineup', {
      target_match_id: matchId,
      target_season_team_id: team.season_team_id,
      target_season_roster_ids: selected,
      target_captain_season_roster_id: captainRosterId,
    });

    setSavingTeamId(null);

    if (saveError) {
      setError(saveError.message);
      return;
    }

    setSuccess(`${team.team_name} lineup saved.`);
    setCaptainPromptTeam(null);
    await loadState();
  }

  if (state.status === 'loading') {
    return <p className="text-sm text-slate-600 dark:text-slate-300">Loading team selection...</p>;
  }

  if (state.status === 'error') {
    return (
      <section>
        <Link className="text-sm font-semibold text-brand-700 hover:underline dark:text-brand-300" to={`/matches${matchesSearch}`}>← Back to matches</Link>
        <h2 className="mt-6 text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Unable to load team selection</h2>
        <p className="mt-4 rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{state.message}</p>
        <button type="button" onClick={() => void loadState()} className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950">Retry</button>
      </section>
    );
  }

  const { selection } = state;
  const isEditable = selection.match.status === 'scheduled';

  return (
    <section className="space-y-6">
      <Link className="text-sm font-semibold text-brand-700 hover:underline dark:text-brand-300" to={`/matches${matchesSearch}`}>← Back to matches</Link>

      <header className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-wide text-brand-600 dark:text-brand-400">Team selection</p>
            <h2 className="mt-1 text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">{selection.teams.map((team) => team.team_name).join(' vs ')}</h2>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">{formatMatchDate(selection.match.match_date)} · {selection.match.venue || 'Community Park'}</p>
          </div>
          <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-bold uppercase tracking-wide text-slate-700 dark:bg-slate-800 dark:text-slate-200">{selection.match.status}</span>
        </div>
        <p className="mt-4 rounded-md bg-brand-50 p-3 text-sm text-brand-900 dark:bg-brand-950/30 dark:text-brand-100">Select between {selection.min_players} and {selection.max_players} players before the match begins.</p>
      </header>

      {error ? <p className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{error}</p> : null}
      {success ? <p className="rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800 dark:border-emerald-900/70 dark:bg-emerald-950/30 dark:text-emerald-200" role="status">{success}</p> : null}

      {selection.teams.length > 1 ? (
        <div className="flex flex-wrap gap-2" role="tablist" aria-label="Team selection">
          {selection.teams.map((team) => (
            <button key={team.season_team_id} type="button" role="tab" aria-selected={activeTeam?.season_team_id === team.season_team_id} onClick={() => setActiveTeamId(team.season_team_id)} className={['min-h-11 rounded-md px-4 py-2 text-sm font-semibold', activeTeam?.season_team_id === team.season_team_id ? 'bg-brand-500 text-slate-950' : 'border border-slate-300 text-slate-700 dark:border-slate-700 dark:text-slate-200'].join(' ')}>{team.team_name}</button>
          ))}
        </div>
      ) : null}

      {activeTeam ? (
        <article className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h3 className="text-xl font-semibold text-slate-950 dark:text-white">{activeTeam.team_name}</h3>
              <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{(selectedByTeam[activeTeam.season_team_id] ?? []).length} of {activeTeam.players.length} players selected.</p>
            </div>
            {!activeTeam.editable ? <span className="text-sm text-slate-500 dark:text-slate-400">View only</span> : null}
          </div>

          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            {activeTeam.players.map((player) => {
              const selected = (selectedByTeam[activeTeam.season_team_id] ?? []).includes(player.season_roster_id);
              return (
                <label key={player.season_roster_id} className={['flex min-h-14 items-center gap-3 rounded-lg border p-3 transition', selected ? 'border-brand-500 bg-brand-50 dark:bg-brand-950/30' : 'border-slate-200 dark:border-slate-800', activeTeam.editable && isEditable ? 'cursor-pointer' : 'cursor-default opacity-80'].join(' ')}>
                  <input type="checkbox" checked={selected} disabled={!activeTeam.editable || !isEditable || savingTeamId === activeTeam.season_team_id} onChange={() => togglePlayer(activeTeam.season_team_id, player.season_roster_id)} className="h-5 w-5 rounded border-slate-300 text-brand-500 focus:ring-brand-500 dark:border-slate-700" />
                  <span className="font-semibold text-slate-950 dark:text-white">{player.display_name}</span>
                </label>
              );
            })}
          </div>

          {activeTeam.editable ? (
            <div className="mt-5 flex flex-wrap items-center gap-3">
              <button type="button" disabled={!isEditable || savingTeamId === activeTeam.season_team_id} onClick={() => promptForCaptain(activeTeam)} className="min-h-11 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 disabled:cursor-not-allowed disabled:opacity-60">{savingTeamId === activeTeam.season_team_id ? 'Saving...' : 'Save lineup'}</button>
              {!isEditable ? <span className="text-sm text-slate-500 dark:text-slate-400">Lineups are locked once the match begins.</span> : null}
            </div>
          ) : null}
        </article>
      ) : (
        <p className="rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">No team selection is available for your assignment in this match.</p>
      )}

      {captainPromptTeam ? (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/50 p-4 sm:items-center" role="presentation">
          <div className="w-full max-w-md rounded-xl bg-white p-5 shadow-xl dark:bg-slate-900" role="dialog" aria-modal="true" aria-labelledby="captain-prompt-title">
            <h3 id="captain-prompt-title" className="text-xl font-semibold text-slate-950 dark:text-white">Choose captain</h3>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Select the captain for {captainPromptTeam.team_name} from the chosen players.</p>
            <div className="mt-4 space-y-2">
              {(selectedByTeam[captainPromptTeam.season_team_id] ?? []).map((rosterId) => {
                const player = captainPromptTeam.players.find((item) => item.season_roster_id === rosterId);
                if (!player) return null;
                return (
                  <label key={rosterId} className="flex min-h-12 cursor-pointer items-center gap-3 rounded-lg border border-slate-200 p-3 dark:border-slate-700">
                    <input type="radio" name="lineup-captain" value={rosterId} checked={captainByTeam[captainPromptTeam.season_team_id] === rosterId} onChange={() => setCaptainByTeam((current) => ({ ...current, [captainPromptTeam.season_team_id]: rosterId }))} className="h-5 w-5 border-slate-300 text-brand-500 focus:ring-brand-500 dark:border-slate-700" />
                    <span className="font-semibold text-slate-950 dark:text-white">{player.display_name}</span>
                  </label>
                );
              })}
            </div>
            <div className="mt-5 flex justify-end gap-3">
              <button type="button" onClick={() => setCaptainPromptTeam(null)} className="min-h-11 rounded-md border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-700 dark:border-slate-700 dark:text-slate-200">Cancel</button>
              <button type="button" disabled={!(selectedByTeam[captainPromptTeam.season_team_id] ?? []).includes(captainByTeam[captainPromptTeam.season_team_id] ?? '') || savingTeamId === captainPromptTeam.season_team_id} onClick={() => void saveTeamSelection(captainPromptTeam)} className="min-h-11 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 disabled:cursor-not-allowed disabled:opacity-60">{savingTeamId === captainPromptTeam.season_team_id ? 'Saving...' : 'Confirm and save'}</button>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
}
