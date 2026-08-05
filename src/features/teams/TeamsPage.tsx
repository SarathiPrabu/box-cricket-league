import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { isSupabaseConfigured, supabase } from "../../lib/supabase";
import { SeasonSelector as SharedSeasonSelector } from "../../components/SeasonSelector";
import { TeamBadge } from "../../components/TeamBadge";

const activeLeagueSlug = "box-cricket-league";

type Season = {
  league_id: string;
  league_name: string;
  season_id: string;
  season_name: string;
  starts_on: string | null;
  ends_on: string | null;
  is_current: boolean;
};

type Team = {
  season_team_id: string;
  team_id: string;
  team_slug: string;
  team_name: string;
  manager_name: string | null;
};

type SeasonsState =
    | { status: "loading" }
    | { status: "error" }
    | { status: "ready"; seasons: Season[] };

type TeamsState =
    | { status: "idle" }
    | { status: "loading" }
    | { status: "error" }
    | { status: "ready"; teams: Team[] };

function seasonSlug(name: string) {
  return name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
}

function TeamRow({
                   team,
                   selectedSeason,
                 }: {
  team: Team;
  selectedSeason: Season;
}) {
  const managerName = team.manager_name?.trim() || "Manager not assigned";
  const teamUrl = `/teams/${team.team_slug}?season=${encodeURIComponent(seasonSlug(selectedSeason.season_name))}`;

  return (
      <tr className="group border-t border-slate-200 transition hover:bg-emerald-50/50 motion-reduce:transition-none dark:border-slate-800 dark:hover:bg-emerald-950/20">
        <td className="px-4 py-3 sm:px-6">
          <Link
              aria-label={`Open ${team.team_name} details for ${selectedSeason.season_name}`}
              className="flex items-center gap-3 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-brand-500/50"
              to={teamUrl}
          >
            <TeamBadge teamName={team.team_name} />
            <span className="font-semibold text-slate-950 group-hover:text-brand-700 dark:text-white dark:group-hover:text-brand-400">
            {team.team_name}
          </span>
          </Link>
        </td>
        <td className="px-4 py-3 text-sm text-slate-600 sm:px-6 dark:text-slate-300">
          {managerName}
        </td>
        <td className="px-4 py-3 text-right sm:px-6">
          <Link
              className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm font-semibold text-brand-700 outline-none transition hover:bg-brand-50 focus-visible:ring-2 focus-visible:ring-brand-500/50 motion-reduce:transition-none dark:text-brand-400 dark:hover:bg-emerald-950/40"
              to={teamUrl}
          >
            View team
            <span
                aria-hidden="true"
                className="transition group-hover:translate-x-0.5 motion-reduce:transition-none"
            >
            →
          </span>
          </Link>
        </td>
      </tr>
  );
}

function TeamRowSkeleton() {
  return (
      <tr className="border-t border-slate-200 dark:border-slate-800">
        <td className="px-4 py-3 sm:px-6">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 shrink-0 animate-pulse rounded-md bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
            <div className="h-4 w-36 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
          </div>
        </td>
        <td className="px-4 py-3 sm:px-6">
          <div className="h-4 w-32 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
        </td>
        <td className="px-4 py-3 sm:px-6">
          <div className="ml-auto h-4 w-20 animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" />
        </td>
      </tr>
  );
}

function TeamsTable({
                      teams,
                      selectedSeason,
                      loading = false,
                    }: {
  teams?: Team[];
  selectedSeason?: Season;
  loading?: boolean;
}) {
  return (
      <div className="mt-6 overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div>
          <table className="w-full table-fixed border-collapse text-left">
            <thead className="bg-slate-50 dark:bg-slate-950/60">
            <tr>
              <th
                  className="px-4 py-3 text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300"
                  scope="col"
              >
                Team
              </th>
              <th
                  className="px-4 py-3 text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300"
                  scope="col"
              >
                Manager
              </th>
              <th
                  className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-slate-600 sm:px-6 dark:text-slate-300"
                  scope="col"
              >
                Action
              </th>
            </tr>
            </thead>
            <tbody>
            {loading
                ? Array.from({ length: 6 }).map((_, index) => (
                    <TeamRowSkeleton key={index} />
                ))
                : teams && selectedSeason
                    ? teams.map((team) => (
                        <TeamRow
                            key={team.season_team_id}
                            selectedSeason={selectedSeason}
                            team={team}
                        />
                    ))
                    : null}
            </tbody>
          </table>
        </div>
      </div>
  );
}

function TeamsCards({ teams, selectedSeason, loading = false }: { teams?: Team[]; selectedSeason?: Season; loading?: boolean }) {
  if (loading) {
    return <div className="mt-6 grid gap-3 md:hidden">{Array.from({ length: 4 }).map((_, index) => <div className="h-24 animate-pulse rounded-lg bg-slate-200 motion-reduce:animate-none dark:bg-slate-800" key={index} />)}</div>;
  }

  if (!teams || !selectedSeason) return null;

  return (
    <ul className="mt-6 grid gap-3 md:hidden">
      {teams.map((team) => {
        const teamUrl = `/teams/${team.team_slug}?season=${encodeURIComponent(seasonSlug(selectedSeason.season_name))}`;
        return (
          <li key={team.season_team_id}>
            <Link className="flex items-center gap-3 rounded-lg border border-slate-200 bg-white p-4 shadow-sm transition hover:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500/50 dark:border-slate-800 dark:bg-slate-900" to={teamUrl}>
              <TeamBadge teamName={team.team_name} />
              <span className="min-w-0 flex-1">
                <span className="block break-words font-semibold text-slate-950 dark:text-white">{team.team_name}</span>
                <span className="mt-1 block text-sm text-slate-600 dark:text-slate-300">{team.manager_name?.trim() || 'Manager not assigned'}</span>
              </span>
              <span className="text-sm font-semibold text-brand-700 dark:text-brand-400" aria-hidden="true">→</span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

export function TeamsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [seasonsState, setSeasonsState] = useState<SeasonsState>({
    status: "loading",
  });
  const [teamsState, setTeamsState] = useState<TeamsState>({ status: "idle" });

  const requestedSeasonSlug = searchParams.get("season");

  const loadSeasons = useCallback(async () => {
    setSeasonsState({ status: "loading" });

    if (!supabase || !isSupabaseConfigured) {
      setSeasonsState({ status: "error" });
      return;
    }

    const { data, error } = await supabase.rpc("get_public_league_seasons", {
      target_league_slug: activeLeagueSlug,
    });

    setSeasonsState(
        error
            ? { status: "error" }
            : { status: "ready", seasons: (data as Season[] | null) ?? [] },
    );
  }, []);

  useEffect(() => {
    void loadSeasons();
  }, [loadSeasons]);

  const selectedSeason = useMemo(() => {
    if (seasonsState.status !== "ready" || seasonsState.seasons.length === 0)
      return null;

    return (
        seasonsState.seasons.find(
            (season) => seasonSlug(season.season_name) === requestedSeasonSlug,
        ) ??
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

  const loadTeams = useCallback(async (season: Season) => {
    setTeamsState({ status: "loading" });

    if (!supabase || !isSupabaseConfigured) {
      setTeamsState({ status: "error" });
      return;
    }

    const { data, error } = await supabase.rpc("get_public_teams_for_season", {
      target_season_id: season.season_id,
    });

    setTeamsState(
        error
            ? { status: "error" }
            : { status: "ready", teams: (data as Team[] | null) ?? [] },
    );
  }, []);

  useEffect(() => {
    if (!selectedSeason) return;
    void loadTeams(selectedSeason);
  }, [loadTeams, selectedSeason]);

  if (seasonsState.status === "loading") {
    return (
        <section>
          <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">
            Teams
          </h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            Loading league seasons.
          </p>
          <TeamsCards loading />
          <div className="hidden md:block"><TeamsTable loading /></div>
        </section>
    );
  }

  if (seasonsState.status === "error") {
    return (
        <section className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <h2 className="text-2xl font-semibold text-slate-950 dark:text-white">
            Unable to load teams
          </h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
            Please try again in a moment.
          </p>
          <button
              className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-brand-400 focus:outline-none focus:ring-2 focus:ring-brand-500/50 motion-reduce:transition-none"
              onClick={() => void loadSeasons()}
              type="button"
          >
            Retry
          </button>
        </section>
    );
  }

  if (!selectedSeason) {
    return (
        <section>
          <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">
            Teams
          </h2>
          <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
            No seasons are available for this league.
          </p>
        </section>
    );
  }

  const leagueName =
      seasonsState.seasons[0]?.league_name ?? "Box Cricket League";

  return (
      <section>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">
              Teams
            </h2>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
              Browse teams in {leagueName}.
            </p>
          </div>
          <SharedSeasonSelector
              id="season-selector"
              onChange={(season) =>
                  setSearchParams({ season: seasonSlug(season.season_name) })
              }
              seasons={seasonsState.seasons}
              selectedSeason={selectedSeason}
          />
        </div>

        {teamsState.status === "loading" || teamsState.status === "idle" ? (
          <>
            <TeamsCards loading />
            <div className="hidden md:block"><TeamsTable loading /></div>
          </>
        ) : null}

        {teamsState.status === "error" ? (
            <div className="mt-6 rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
              <p className="text-sm text-slate-600 dark:text-slate-300">
                Unable to load teams right now.
              </p>
              <button
                  className="mt-4 rounded-md bg-brand-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-brand-400 focus:outline-none focus:ring-2 focus:ring-brand-500/50 motion-reduce:transition-none"
                  onClick={() => void loadTeams(selectedSeason)}
                  type="button"
              >
                Retry
              </button>
            </div>
        ) : null}

        {teamsState.status === "ready" && teamsState.teams.length === 0 ? (
            <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
              No teams are registered for this season.
            </p>
        ) : null}

        {teamsState.status === "ready" && teamsState.teams.length > 0 ? (
          <>
            <TeamsCards selectedSeason={selectedSeason} teams={teamsState.teams} />
            <div className="hidden md:block"><TeamsTable selectedSeason={selectedSeason} teams={teamsState.teams} /></div>
          </>
        ) : null}
      </section>
  );
}
