import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';
import { SeasonSelector as SharedSeasonSelector } from '../../components/SeasonSelector';
import { InfoCard, StandingsTable } from '../../components/StandingsTable';

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
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Standings</h2>
        <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Loading league seasons.</p>
        <StandingsTable loading />
      </section>
    );
  }

  if (seasonsState.status === 'error') {
    return <InfoCard message="Please try again in a moment." title="Unable to load standings" />;
  }

  if (!selectedSeason) {
    return (
      <section>
        <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Standings</h2>
        <InfoCard className="mt-6" message="No seasons are available for this league." />
      </section>
    );
  }

  const leagueName = seasonsState.seasons[0]?.league_name ?? 'Box Cricket League';

  return (
    <section>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-xl font-semibold text-slate-950 sm:text-2xl dark:text-white">
            {leagueName} {selectedSeason.season_name} Points Table &amp; Team Standings
          </h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            Points: win 2, tie/no result 1. NRR breaks ties.
          </p>
        </div>
        <SharedSeasonSelector
          id="standings-season-selector"
          onChange={(season) => setSearchParams({ season: seasonSlug(season.season_name) })}
          seasons={seasonsState.seasons}
          selectedSeason={selectedSeason}
        />
      </div>

      {standingsState.status === 'loading' || standingsState.status === 'idle' ? <StandingsTable loading /> : null}

      {standingsState.status === 'error' ? (
        <InfoCard className="mt-6" message="Unable to load standings right now." />
      ) : null}

      {standingsState.status === 'ready' && standingsState.standings.length === 0 ? (
        <InfoCard className="mt-6" message="No completed matches have been recorded for this season yet." />
      ) : null}

      {standingsState.status === 'ready' && standingsState.standings.length > 0 ? (
        <StandingsTable
          seasonSlugValue={seasonSlug(selectedSeason.season_name)}
          selectedSeason={selectedSeason}
          standings={standingsState.standings}
        />
      ) : null}
    </section>
  );
}
