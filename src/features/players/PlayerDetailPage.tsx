import { useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

type Player = {
  id: string;
  display_name: string;
  full_name: string | null;
};

type SeasonStats = {
  season_id: string;
  season_name: string;
  starts_on: string | null;
  team_name: string;
  matches_played: number;
  runs: number;
  balls_faced: number;
  fours: number;
  sixes: number;
  balls_bowled: number;
  runs_conceded: number;
  wickets: number;
  catches: number;
  stumpings: number;
  player_of_match_count: number;
};

type ProfileState =
  | { status: 'loading' }
  | { status: 'not-found' }
  | { status: 'error' }
  | { status: 'ready'; player: Player; seasons: SeasonStats[] };

const emptyStats: Omit<SeasonStats, 'season_id' | 'season_name' | 'starts_on' | 'team_name'> = {
  matches_played: 0,
  runs: 0,
  balls_faced: 0,
  fours: 0,
  sixes: 0,
  balls_bowled: 0,
  runs_conceded: 0,
  wickets: 0,
  catches: 0,
  stumpings: 0,
  player_of_match_count: 0,
};

function formatRate(numerator: number, denominator: number, multiplier: number) {
  return denominator === 0 ? '—' : ((numerator / denominator) * multiplier).toFixed(2);
}

function StatGroup({ title, stats }: { title: string; stats: Array<[string, string | number]> }) {
  return (
    <section className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <h3 className="text-lg font-semibold text-slate-950 dark:text-white">{title}</h3>
      <dl className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3">
        {stats.map(([label, value]) => (
          <div key={label}>
            <dt className="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400">{label}</dt>
            <dd className="mt-1 text-xl font-semibold text-slate-950 dark:text-white">{value}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function SeasonHistoryCards({ seasons }: { seasons: SeasonStats[] }) {
  return (
    <ul className="divide-y divide-slate-200 dark:divide-slate-800 md:hidden">
      {seasons.map((season) => (
        <li className="p-4" key={season.season_id}>
          <p className="font-semibold text-slate-950 dark:text-white">{season.season_name}</p>
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{season.team_name}</p>
          <dl className="mt-4 grid grid-cols-3 gap-3 text-center text-sm">
            <div><dt className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">Matches</dt><dd className="mt-1 font-semibold">{season.matches_played}</dd></div>
            <div><dt className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">Runs</dt><dd className="mt-1 font-semibold">{season.runs}</dd></div>
            <div><dt className="text-xs uppercase tracking-wide text-slate-500 dark:text-slate-400">Wickets</dt><dd className="mt-1 font-semibold">{season.wickets}</dd></div>
          </dl>
        </li>
      ))}
    </ul>
  );
}

export function PlayerDetailPage() {
  const { slug } = useParams();
  const [profile, setProfile] = useState<ProfileState>({ status: 'loading' });
  const [selectedSeasonId, setSelectedSeasonId] = useState<string>('career');

  useEffect(() => {
    let cancelled = false;

    async function loadProfile() {
      if (!slug || !supabase || !isSupabaseConfigured) {
        if (!cancelled) setProfile({ status: 'error' });
        return;
      }

      const { data: playerData, error: playerError } = await supabase.rpc('get_public_player_by_slug', {
        player_slug: slug,
      });
      const player = (playerData as Player[] | null)?.[0];

      if (playerError) {
        if (!cancelled) setProfile({ status: 'error' });
        return;
      }

      if (!player) {
        if (!cancelled) setProfile({ status: 'not-found' });
        return;
      }

      const { data: seasonData, error: seasonError } = await supabase.rpc(
        'get_public_player_season_stats',
        { target_player_id: player.id },
      );

      if (!cancelled) {
        setProfile(
          seasonError
            ? { status: 'error' }
            : { status: 'ready', player, seasons: (seasonData as SeasonStats[] | null) ?? [] },
        );
      }
    }

    void loadProfile();
    return () => {
      cancelled = true;
    };
  }, [slug]);

  const stats = useMemo(() => {
    if (profile.status !== 'ready') return emptyStats;
    const seasons =
      selectedSeasonId === 'career'
        ? profile.seasons
        : profile.seasons.filter((season) => season.season_id === selectedSeasonId);

    return seasons.reduce(
      (total, season) => ({
        matches_played: total.matches_played + season.matches_played,
        runs: total.runs + season.runs,
        balls_faced: total.balls_faced + season.balls_faced,
        fours: total.fours + season.fours,
        sixes: total.sixes + season.sixes,
        balls_bowled: total.balls_bowled + season.balls_bowled,
        runs_conceded: total.runs_conceded + season.runs_conceded,
        wickets: total.wickets + season.wickets,
        catches: total.catches + season.catches,
        stumpings: total.stumpings + season.stumpings,
        player_of_match_count: total.player_of_match_count + season.player_of_match_count,
      }),
      emptyStats,
    );
  }, [profile, selectedSeasonId]);

  if (profile.status === 'loading') {
    return <p className="text-sm text-slate-600 dark:text-slate-300">Loading player profile…</p>;
  }

  if (profile.status === 'not-found') {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">Player not found</h2>
        <Link className="mt-3 inline-block text-sm font-medium text-brand-600 dark:text-brand-400" to="/players">
          Back to players
        </Link>
      </section>
    );
  }

  if (profile.status === 'error') {
    return <p className="text-sm text-slate-600 dark:text-slate-300">Unable to load this player profile right now.</p>;
  }

  return (
    <div className="space-y-6">
      <header>
        <Link className="text-sm font-medium text-brand-600 dark:text-brand-400" to="/players">
          ← Players
        </Link>
        <h2 className="mt-3 break-words text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">{profile.player.display_name}</h2>
        {profile.player.full_name && profile.player.full_name !== profile.player.display_name ? (
          <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{profile.player.full_name}</p>
        ) : null}
      </header>

      <div className="flex flex-wrap gap-2" aria-label="Statistic season selector">
        <button
          className={`min-h-11 rounded-md px-4 py-2 text-sm font-medium ${selectedSeasonId === 'career' ? 'bg-brand-500 text-slate-950' : 'bg-white text-slate-700 dark:bg-slate-900 dark:text-slate-300'}`}
          onClick={() => setSelectedSeasonId('career')}
          type="button"
        >
          Career
        </button>
        {profile.seasons.map((season) => (
          <button
            key={season.season_id}
            className={`min-h-11 rounded-md px-4 py-2 text-sm font-medium ${selectedSeasonId === season.season_id ? 'bg-brand-500 text-slate-950' : 'bg-white text-slate-700 dark:bg-slate-900 dark:text-slate-300'}`}
            onClick={() => setSelectedSeasonId(season.season_id)}
            type="button"
          >
            {season.season_name}
          </button>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <StatGroup title="Batting" stats={[
          ['Matches', stats.matches_played], ['Runs', stats.runs], ['Balls faced', stats.balls_faced],
          ['Strike rate', formatRate(stats.runs, stats.balls_faced, 100)], ['Fours', stats.fours], ['Sixes', stats.sixes],
        ]} />
        <StatGroup title="Bowling" stats={[
          ['Wickets', stats.wickets], ['Balls bowled', stats.balls_bowled], ['Runs conceded', stats.runs_conceded],
          ['Economy', formatRate(stats.runs_conceded, stats.balls_bowled, 6)],
        ]} />
        <StatGroup title="Fielding" stats={[
          ['Catches', stats.catches], ['Stumpings', stats.stumpings],
        ]} />
        <StatGroup title="Awards" stats={[
          ['Player of the match', stats.player_of_match_count],
        ]} />
      </div>

      <section className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div className="p-5"><h3 className="text-lg font-semibold text-slate-950 dark:text-white">Season history</h3></div>
        {profile.seasons.length === 0 ? (
          <p className="border-t border-slate-200 px-5 py-4 text-sm text-slate-600 dark:border-slate-800 dark:text-slate-300">No season records yet.</p>
        ) : (
          <>
          <SeasonHistoryCards seasons={profile.seasons} />
          <div className="hidden md:block">
            <table className="w-full text-left text-sm">
              <thead className="border-y border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500 dark:border-slate-800 dark:bg-slate-950 dark:text-slate-400">
                <tr><th className="px-5 py-3">Season</th><th className="px-5 py-3">Team</th><th className="px-5 py-3">Matches</th><th className="px-5 py-3">Runs</th><th className="px-5 py-3">Wickets</th></tr>
              </thead>
              <tbody>
                {profile.seasons.map((season) => (
                  <tr className="border-b border-slate-200 last:border-0 dark:border-slate-800" key={season.season_id}>
                    <td className="px-5 py-3 font-medium text-slate-950 dark:text-white">{season.season_name}</td><td className="px-5 py-3">{season.team_name}</td><td className="px-5 py-3">{season.matches_played}</td><td className="px-5 py-3">{season.runs}</td><td className="px-5 py-3">{season.wickets}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          </>
        )}
      </section>
    </div>
  );
}
