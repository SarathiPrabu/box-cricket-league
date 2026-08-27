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

type PlayerStats = {
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

type StatsTab = 'overall' | 'batting' | 'bowling';
type SortKey = keyof Pick<PlayerStats, 'player_name' | 'matches_played' | 'runs' | 'balls_faced' | 'fours' | 'sixes' | 'balls_bowled' | 'dot_balls_bowled' | 'runs_conceded' | 'wickets' | 'catches' | 'stumpings' | 'player_of_match_count'>;

const statTabLabels: Record<StatsTab, string> = { overall: 'Overall', batting: 'Batting', bowling: 'Bowling' };
const statColumns: Record<StatsTab, { key: SortKey; label: string }[]> = {
  overall: [{ key: 'matches_played', label: 'Matches' }, { key: 'runs', label: 'Runs' }, { key: 'wickets', label: 'Wickets' }],
  batting: [{ key: 'matches_played', label: 'Matches' }, { key: 'runs', label: 'Runs' }, { key: 'balls_faced', label: 'Balls' }, { key: 'fours', label: '4s' }, { key: 'sixes', label: '6s' }],
  bowling: [{ key: 'matches_played', label: 'Matches' }, { key: 'balls_bowled', label: 'Balls' }, { key: 'dot_balls_bowled', label: 'Dots' }, { key: 'runs_conceded', label: 'Runs' }, { key: 'wickets', label: 'Wickets' }],
};

function formatRate(value: number, total: number, multiplier: number) {
  return total ? ((value / total) * multiplier).toFixed(2) : '—';
}

type TeamMatch = {
  match_id: string;
  home_season_team_id: string;
  home_team_name: string;
  away_season_team_id: string;
  away_team_name: string;
  match_date: string | null;
  status: 'completed' | 'scheduled' | 'live' | 'draft' | 'cancelled';
  result_type: 'win' | 'tie' | 'no_result' | 'forfeit' | null;
  winner_team_name: string | null;
};

type TeamState =
    | { status: 'loading' }
    | { status: 'not-found' }
    | { status: 'error' }
    | { status: 'ready'; team: TeamDetail; roster: RosterPlayer[]; stats: PlayerStats[]; results: TeamMatch[] };

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
  const [statsTab, setStatsTab] = useState<StatsTab>('overall');
  const [sort, setSort] = useState<{ key: SortKey; direction: 'asc' | 'desc' }>({ key: 'runs', direction: 'desc' });

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

      const [rosterResult, leaderboardResult, matchesResult] = await Promise.all([
        supabase.rpc('get_public_team_roster', { target_season_team_id: team.season_team_id }),
        supabase.rpc('get_public_season_leaderboards', { target_season_id: team.season_id }),
        supabase.rpc('get_public_matches_for_season', { target_season_id: team.season_id }),
      ]);

      const rosterData = rosterResult.data;
      const rosterError = rosterResult.error;
      const teamStats = ((leaderboardResult.data as PlayerStats[] | null) ?? []).filter((row) => row.team_name === team.team_name);
      const results = ((matchesResult.data as TeamMatch[] | null) ?? [])
        .filter((match) => match.status === 'completed' && (match.home_season_team_id === team.season_team_id || match.away_season_team_id === team.season_team_id))
        .sort((first, second) => Date.parse(second.match_date ?? '') - Date.parse(first.match_date ?? ''))
        .slice(0, 3);

      if (!cancelled) {
        setTeamState(
            rosterError
                ? { status: 'error' }
                : {
                  status: 'ready',
                  team,
                  roster: (rosterData as RosterPlayer[] | null) ?? [],
                  stats: teamStats,
                  results,
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

  const { roster, team, stats, results } = teamState;
  const managerName = team.manager_name?.trim() || 'Manager not assigned';
  const statsByPlayer = new Map(stats.map((row) => [row.player_id, row]));
  const topScorer = [...stats].sort((first, second) => second.runs - first.runs)[0];
  const topWicketTaker = [...stats].sort((first, second) => second.wickets - first.wickets)[0];
  const visibleColumns = statColumns[statsTab];
  const statsRows = roster.map((player) => statsByPlayer.get(player.player_id) ?? {
    player_id: player.player_id, player_slug: player.player_slug, player_name: player.display_name, team_name: team.team_name,
    matches_played: 0, runs: 0, balls_faced: 0, fours: 0, sixes: 0, balls_bowled: 0, dot_balls_bowled: 0,
    runs_conceded: 0, wickets: 0, catches: 0, stumpings: 0, player_of_match_count: 0,
  });
  const sortedStats = [...statsRows].sort((first, second) => {
    const firstValue = first[sort.key];
    const secondValue = second[sort.key];
    const comparison = typeof firstValue === 'string' && typeof secondValue === 'string'
      ? firstValue.localeCompare(secondValue)
      : Number(firstValue) - Number(secondValue);
    return sort.direction === 'asc' ? comparison : -comparison;
  });

  function sortBy(key: SortKey) {
    setSort((current) => ({ key, direction: current.key === key && current.direction === 'desc' ? 'asc' : 'desc' }));
  }

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

          <div className="mt-4 flex gap-1 overflow-x-auto rounded-lg border border-slate-200 bg-slate-100 p-1 dark:border-slate-800 dark:bg-slate-950" role="tablist" aria-label="Team statistics views">
            {(Object.keys(statTabLabels) as StatsTab[]).map((tab) => <button className={`min-h-11 shrink-0 rounded-md px-4 text-sm font-semibold transition ${statsTab === tab ? 'bg-white text-slate-950 shadow-sm dark:bg-slate-800 dark:text-white' : 'text-slate-600 dark:text-slate-300'}`} key={tab} onClick={() => setStatsTab(tab)} role="tab" aria-selected={statsTab === tab} type="button">{statTabLabels[tab]}</button>)}
          </div>

          {roster.length === 0 ? (
              <p className="mt-4 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
                No players have been assigned to this team yet.
              </p>
          ) : (
              <div className="mt-4 overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
                <div className="overflow-x-auto">
                  <table className="min-w-[560px] w-full text-left text-sm">
                    <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500 dark:bg-slate-950 dark:text-slate-400">
                      <tr><th className="px-4 py-3">Player</th>{visibleColumns.map((column) => <th className="px-4 py-3" key={column.key}><button className="flex min-h-8 items-center gap-1 whitespace-nowrap font-bold" onClick={() => sortBy(column.key)} type="button">{column.label}<span aria-hidden="true">{sort.key === column.key ? (sort.direction === 'asc' ? '↑' : '↓') : '↕'}</span></button></th>)}{statsTab === 'batting' ? <th className="px-4 py-3">Strike rate</th> : null}{statsTab === 'bowling' ? <th className="px-4 py-3">Economy</th> : null}</tr>
                    </thead>
                    <tbody className="divide-y divide-slate-200 dark:divide-slate-800">
                      {sortedStats.map((row) => {
                        const player = roster.find((item) => item.player_id === row.player_id);
                        if (!player) return null;
                        return <tr key={player.season_roster_id}>
                          <td className="px-4 py-3"><Link className="font-semibold text-slate-950 hover:text-brand-600 dark:text-white" to={`/players/${player.player_slug}`}>{player.display_name}</Link>{player.is_manager ? <span className="ml-2 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300">Manager</span> : null}</td>
                          {visibleColumns.map((column) => <td className="px-4 py-3 font-semibold text-slate-950 dark:text-white" key={column.key}>{row[column.key]}</td>)}
                          {statsTab === 'batting' ? <td className="px-4 py-3 font-semibold text-slate-950 dark:text-white">{formatRate(row.runs, row.balls_faced, 100)}</td> : null}{statsTab === 'bowling' ? <td className="px-4 py-3 font-semibold text-slate-950 dark:text-white">{formatRate(row.runs_conceded, row.balls_bowled, 6)}</td> : null}
                        </tr>;
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
          )}
        </section>

        <section className="grid gap-4 md:grid-cols-3">
          {[['Top scorer', topScorer, 'runs', 'Runs'], ['Top wicket taker', topWicketTaker, 'wickets', 'Wickets']].map(([label, player, stat, statLabel]) => (
            <article className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900" key={label as string}>
              <p className="text-xs font-bold uppercase tracking-wide text-brand-600 dark:text-brand-400">{label as string}</p>
              <p className="mt-3 text-lg font-semibold text-slate-950 dark:text-white">{(player as PlayerStats | undefined)?.player_name ?? 'No stats yet'}</p>
              <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{(player as PlayerStats | undefined)?.[stat as 'runs' | 'wickets'] ?? 0} {statLabel as string}</p>
            </article>
          ))}
          <article className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <p className="text-xs font-bold uppercase tracking-wide text-brand-600 dark:text-brand-400">Recent results</p>
            <div className="mt-3 space-y-3">{results.length ? results.map((match) => <div className="border-b border-slate-100 pb-2 last:border-0 last:pb-0 dark:border-slate-800" key={match.match_id}><p className="text-sm font-semibold text-slate-950 dark:text-white">{match.home_team_name} vs {match.away_team_name}</p><p className="text-xs text-slate-500 dark:text-slate-400">{match.result_type === 'forfeit' ? `${match.winner_team_name} won by forfeit` : match.result_type === 'win' ? `${match.winner_team_name} won` : match.result_type === 'tie' ? 'Tie' : 'No result'}</p></div>) : <p className="text-sm text-slate-600 dark:text-slate-300">No completed results yet.</p>}</div>
          </article>
        </section>
      </div>
  );
}
