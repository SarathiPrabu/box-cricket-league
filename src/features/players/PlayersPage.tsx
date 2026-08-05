import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

type PlayerListItem = {
  id: string;
  slug: string;
  display_name: string;
  full_name: string | null;
};

type PlayersState =
  | { status: 'loading' }
  | { status: 'error' }
  | { status: 'ready'; players: PlayerListItem[] };

export function PlayersPage() {
  const [playersState, setPlayersState] = useState<PlayersState>({ status: 'loading' });

  useEffect(() => {
    let cancelled = false;

    async function loadPlayers() {
      if (!supabase || !isSupabaseConfigured) {
        if (!cancelled) setPlayersState({ status: 'error' });
        return;
      }

      const { data, error } = await supabase.rpc('get_public_players');

      if (!cancelled) {
        setPlayersState(
          error
            ? { status: 'error' }
            : { status: 'ready', players: (data as PlayerListItem[] | null) ?? [] },
        );
      }
    }

    void loadPlayers();
    return () => {
      cancelled = true;
    };
  }, []);

  if (playersState.status === 'loading') {
    return <p className="text-sm text-slate-600 dark:text-slate-300">Loading players…</p>;
  }

  if (playersState.status === 'error') {
    return <p className="text-sm text-slate-600 dark:text-slate-300">Unable to load players right now.</p>;
  }

  return (
    <section>
      <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Players</h2>
      <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Browse player profiles and career statistics.</p>

      {playersState.players.length === 0 ? (
        <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
          No players have been added yet.
        </p>
      ) : (
        <ul className="mt-6 grid gap-3 sm:grid-cols-2">
          {playersState.players.map((player) => (
            <li key={player.id}>
              <Link
                className="block rounded-lg border border-slate-200 bg-white p-5 shadow-sm transition hover:border-brand-500 dark:border-slate-800 dark:bg-slate-900"
                to={`/players/${player.slug}`}
              >
                <p className="font-semibold text-slate-950 dark:text-white">{player.display_name}</p>
                {player.full_name && player.full_name !== player.display_name ? (
                  <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">{player.full_name}</p>
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
