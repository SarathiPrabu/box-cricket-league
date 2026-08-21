import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom';
import { SeasonSelector } from '../../components/SeasonSelector';
import { useAuth } from '../auth/authState';
import { hasRoleForLeague } from '../../app/routeAuthorization';
import { roleAccessEnabled } from '../../app/accessMode';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';
import { MatchCard, type MatchCardData } from '../../components/MatchCard';

const leagueSlug = 'box-cricket-league';
const communityPark = 'Community Park';
const noDateGroupKey = 'no-date';

function parsePage(value: string | null) {
  const page = Number(value);
  return Number.isInteger(page) && page > 0 ? page : 1;
}

type Season = {
  league_id: string;
  league_name: string;
  season_id: string;
  season_name: string;
  is_current: boolean;
};

type Team = { season_team_id: string; team_name: string };

type Match = MatchCardData & {
  match_id: string;
  season_id: string;
  home_season_team_id: string;
  away_season_team_id: string;
};

type MatchDateGroup = {
  dateKey: string | null;
  matches: Match[];
};

function seasonSlug(name: string) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

function toDateTimeLocal(value: string | null) {
  if (!value) return '';
  const date = new Date(value);
  const pad = (number: number) => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function localDateKey(value: string | null) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const pad = (number: number) => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function formatMatchDay(dateKey: string | null) {
  if (!dateKey) return 'Date to be confirmed';
  const [year, month, day] = dateKey.split('-').map(Number);
  return new Intl.DateTimeFormat(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }).format(new Date(year, month - 1, day));
}

function compareMatchesBySchedule(first: Match, second: Match) {
  const firstDateKey = localDateKey(first.match_date);
  const secondDateKey = localDateKey(second.match_date);

  if (firstDateKey !== secondDateKey) {
    if (!firstDateKey) return 1;
    if (!secondDateKey) return -1;
    return secondDateKey.localeCompare(firstDateKey);
  }

  if (!first.match_date || !second.match_date) return 0;
  return new Date(first.match_date).getTime() - new Date(second.match_date).getTime();
}

type MatchPaginationProps = {
  pageCount: number;
  currentPage: number;
  onPageChange: (page: number) => void;
};

function MatchPagination({ pageCount, currentPage, onPageChange }: MatchPaginationProps) {
  if (pageCount <= 1) return null;

  return (
    <nav className="mt-3 flex flex-wrap items-center justify-center gap-1.5" aria-label="Matches pages">
      <button type="button" disabled={currentPage === 1} onClick={() => onPageChange(Math.max(1, currentPage - 1))} className="min-h-9 rounded-md border border-slate-300 px-2 text-xs font-semibold text-slate-700 disabled:cursor-not-allowed disabled:opacity-50 dark:border-slate-700 dark:text-slate-200">Prev</button>
      {Array.from({ length: pageCount }, (_, index) => index + 1).map((page) => <button key={page} type="button" aria-current={page === currentPage ? 'page' : undefined} onClick={() => onPageChange(page)} className={`min-h-9 min-w-9 rounded-md border px-2 text-xs font-semibold ${page === currentPage ? 'border-brand-500 bg-brand-500 text-slate-950' : 'border-slate-300 text-slate-700 dark:border-slate-700 dark:text-slate-200'}`}>{page}</button>)}
      <button type="button" disabled={currentPage === pageCount} onClick={() => onPageChange(Math.min(pageCount, currentPage + 1))} className="min-h-9 rounded-md border border-slate-300 px-2 text-xs font-semibold text-slate-700 disabled:cursor-not-allowed disabled:opacity-50 dark:border-slate-700 dark:text-slate-200">Next</button>
    </nav>
  );
}

export function MatchesPage() {
  const { user } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [seasons, setSeasons] = useState<Season[] | null>(null);
  const [teams, setTeams] = useState<Team[]>([]);
  const [matches, setMatches] = useState<Match[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [homeTeamId, setHomeTeamId] = useState('');
  const [awayTeamId, setAwayTeamId] = useState('');
  const [matchDate, setMatchDate] = useState('');
  const [editingMatchId, setEditingMatchId] = useState<string | null>(null);
  const [editingHomeTeamId, setEditingHomeTeamId] = useState('');
  const [editingAwayTeamId, setEditingAwayTeamId] = useState('');
  const [editingMatchDate, setEditingMatchDate] = useState('');

  const requestedSeason = searchParams.get('season');
  const requestedPage = searchParams.get('page');
  const requestedMatchId = location.hash.startsWith('#match-') ? location.hash.slice('#match-'.length) : null;
  const currentPage = parsePage(requestedPage);
  const selectedSeason = useMemo(() => {
    if (!seasons?.length) return null;
    return seasons.find((season) => seasonSlug(season.season_name) === requestedSeason) ?? seasons.find((season) => season.is_current) ?? seasons[0];
  }, [requestedSeason, seasons]);
  const isAdmin = !roleAccessEnabled || Boolean(
    user && hasRoleForLeague(user.roles, ['admin'], leagueSlug, user.activeRole),
  );
  const canManageSelection = !roleAccessEnabled || Boolean(
    user && hasRoleForLeague(user.roles, ['admin', 'team_manager'], leagueSlug, user.activeRole),
  );
  const matchDateGroups = useMemo<MatchDateGroup[]>(() => {
    if (!matches) return [];

    const groups = new Map<string, MatchDateGroup>();
    [...matches].sort(compareMatchesBySchedule).forEach((match) => {
      const dateKey = localDateKey(match.match_date);
      const groupKey = dateKey ?? noDateGroupKey;
      const group = groups.get(groupKey);
      if (group) {
        group.matches.push(match);
      } else {
        groups.set(groupKey, { dateKey, matches: [match] });
      }
    });
    return [...groups.values()];
  }, [matches]);
  const pageCount = matchDateGroups.length;
  const activePageIndex = pageCount ? Math.min(currentPage - 1, pageCount - 1) : 0;
  const activeDateGroup = matchDateGroups[activePageIndex];

  useEffect(() => {
    if (pageCount > 0 && currentPage > pageCount) {
      const nextSearchParams = new URLSearchParams(searchParams);
      nextSearchParams.set('page', String(pageCount));
      setSearchParams(nextSearchParams, { replace: true });
    }
  }, [currentPage, pageCount, searchParams, setSearchParams]);
  useEffect(() => {
    if (!requestedMatchId || !activeDateGroup?.matches.some((match) => match.match_id === requestedMatchId)) return;
    document.getElementById(`match-${requestedMatchId}`)?.scrollIntoView({ block: 'start' });
  }, [activeDateGroup, requestedMatchId]);

  function changePage(page: number) {
    const nextSearchParams = new URLSearchParams(searchParams);
    nextSearchParams.set('page', String(page));
    setSearchParams(nextSearchParams);
  }

  const loadSeasons = useCallback(async () => {
    if (!supabase || !isSupabaseConfigured) {
      setError('Supabase is not configured.');
      return;
    }
    const { data, error: loadError } = await supabase.rpc('get_public_league_seasons', { target_league_slug: leagueSlug });
    if (loadError) setError(loadError.message);
    else setSeasons((data as Season[] | null) ?? []);
  }, []);

  const loadSeasonData = useCallback(async (season: Season) => {
    if (!supabase || !isSupabaseConfigured) return;
    setMatches(null);
    const [teamsResult, matchesResult] = await Promise.all([
      supabase.rpc('get_public_teams_for_season', { target_season_id: season.season_id }),
      supabase.rpc('get_public_matches_for_season', { target_season_id: season.season_id }),
    ]);
    if (teamsResult.error || matchesResult.error) {
      setError(teamsResult.error?.message ?? matchesResult.error?.message ?? 'Unable to load matches.');
      return;
    }
    setTeams(((teamsResult.data ?? []) as Team[]));
    setMatches(((matchesResult.data ?? []) as Match[]));
  }, []);

  useEffect(() => { void loadSeasons(); }, [loadSeasons]);
  useEffect(() => {
    if (!selectedSeason) return;
    const slug = seasonSlug(selectedSeason.season_name);
    if (requestedSeason !== slug) {
      const nextSearchParams = new URLSearchParams(searchParams);
      nextSearchParams.set('season', slug);
      navigate({ search: `?${nextSearchParams.toString()}`, hash: location.hash }, { replace: true });
    }
  }, [location.hash, navigate, requestedSeason, searchParams, selectedSeason]);
  useEffect(() => {
    if (selectedSeason) void loadSeasonData(selectedSeason);
  }, [loadSeasonData, selectedSeason]);

  async function saveMatch(status: 'draft' | 'scheduled') {
    if (!supabase || !selectedSeason || !homeTeamId || !awayTeamId || !matchDate || homeTeamId === awayTeamId) {
      setError('Choose two different teams and a date and time.');
      return;
    }
    setSaving(true);
    setError(null);
    const { error: saveError } = await supabase.from('matches').insert({
      season_id: selectedSeason.season_id,
      home_season_team_id: homeTeamId,
      away_season_team_id: awayTeamId,
      match_date: new Date(matchDate).toISOString(),
      venue: communityPark,
      status,
    });
    setSaving(false);
    if (saveError) { setError(saveError.message); return; }
    setHomeTeamId('');
    setAwayTeamId('');
    setMatchDate('');
    await loadSeasonData(selectedSeason);
  }

  async function publishMatch(matchId: string) {
    if (!supabase || !selectedSeason) return;
    const { error: publishError } = await supabase.from('matches').update({ status: 'scheduled' }).eq('id', matchId);
    if (publishError) { setError(publishError.message); return; }
    await loadSeasonData(selectedSeason);
  }

  function startEditing(match: Match) {
    setError(null);
    setEditingMatchId(match.match_id);
    setEditingHomeTeamId(match.home_season_team_id);
    setEditingAwayTeamId(match.away_season_team_id);
    setEditingMatchDate(toDateTimeLocal(match.match_date));
  }

  async function updateMatch(matchId: string) {
    if (!supabase || !selectedSeason || !editingHomeTeamId || !editingAwayTeamId || !editingMatchDate || editingHomeTeamId === editingAwayTeamId) {
      setError('Choose two different teams and a date and time.');
      return;
    }
    setSaving(true);
    setError(null);
    const { error: updateError } = await supabase.from('matches').update({
      home_season_team_id: editingHomeTeamId,
      away_season_team_id: editingAwayTeamId,
      match_date: new Date(editingMatchDate).toISOString(),
    }).eq('id', matchId);
    setSaving(false);
    if (updateError) { setError(updateError.message); return; }
    setEditingMatchId(null);
    await loadSeasonData(selectedSeason);
  }

  async function deleteMatch(matchId: string) {
    if (!supabase || !selectedSeason || !window.confirm('Delete this scheduled match? This cannot be undone.')) return;
    setSaving(true);
    setError(null);
    const { error: deleteError } = await supabase.from('matches').delete().eq('id', matchId);
    setSaving(false);
    if (deleteError) { setError(deleteError.message); return; }
    setEditingMatchId(null);
    await loadSeasonData(selectedSeason);
  }

  return (
    <section>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-2xl font-semibold text-slate-950 sm:text-3xl dark:text-white">Matches</h2>
          <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">Fixtures and live match updates.</p>
        </div>
        {selectedSeason && seasons ? <SeasonSelector id="matches-season-selector" seasons={seasons} selectedSeason={selectedSeason} onChange={(season) => setSearchParams({ season: seasonSlug(season.season_name) })} /> : null}
      </div>

      {isAdmin && selectedSeason ? (
        <form className="mt-6 rounded-lg border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-800 dark:bg-slate-900" onSubmit={(event) => { event.preventDefault(); void saveMatch('scheduled'); }}>
          <h3 className="font-semibold text-slate-950 dark:text-white">Schedule a match</h3>
          <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Home team<select required value={homeTeamId} onChange={(event) => setHomeTeamId(event.target.value)} className="form-select mt-1"><option value="">Choose team</option>{teams.map((team) => <option key={team.season_team_id} value={team.season_team_id}>{team.team_name}</option>)}</select></label>
          <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Away team<select required value={awayTeamId} onChange={(event) => setAwayTeamId(event.target.value)} className="form-select mt-1"><option value="">Choose team</option>{teams.map((team) => <option key={team.season_team_id} value={team.season_team_id} disabled={team.season_team_id === homeTeamId}>{team.team_name}</option>)}</select></label>
            <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Date and time<input required type="datetime-local" value={matchDate} onChange={(event) => setMatchDate(event.target.value)} className="mt-1 block min-h-11 w-full rounded-md border border-slate-300 bg-white px-3 dark:border-slate-700 dark:bg-slate-950 dark:text-white" /></label>
            <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Venue<input disabled value={communityPark} className="mt-1 block min-h-11 w-full rounded-md border border-slate-300 bg-slate-100 px-3 text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300" /></label>
          </div>
          <div className="mt-4 flex flex-wrap gap-3"><button type="button" disabled={saving} onClick={() => void saveMatch('draft')} className="min-h-11 rounded-md border border-slate-300 px-4 text-sm font-semibold dark:border-slate-700">Save draft</button><button disabled={saving} type="submit" className="min-h-11 rounded-md bg-brand-500 px-4 text-sm font-semibold text-slate-950">Publish match</button></div>
        </form>
      ) : null}

      {error ? <p className="mt-6 rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300" role="alert">{error}</p> : null}
      {seasons?.length === 0 ? <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">No seasons are available for this league yet.</p> : null}
      {selectedSeason && (matches === null ? <p className="mt-6 text-sm text-slate-600 dark:text-slate-300">Loading matches...</p> : matches.length === 0 ? <p className="mt-6 rounded-lg border border-slate-200 bg-white p-5 text-sm text-slate-600 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">No published matches for this season yet.</p> : <>
        <div className="mt-6">
          <h3 className="text-lg font-semibold text-slate-950 dark:text-white">{formatMatchDay(activeDateGroup?.dateKey ?? null)}</h3>
          <MatchPagination pageCount={pageCount} currentPage={activePageIndex + 1} onPageChange={changePage} />
          <ul className="mt-3 grid gap-3">{activeDateGroup?.matches.map((match) => {
            const canEdit = isAdmin && match.status === 'scheduled';
            const isEditing = editingMatchId === match.match_id;

            return <MatchCard id={`match-${match.match_id}`} key={match.match_id} canEdit={canEdit} isEditing={isEditing} match={match} onEditToggle={canEdit ? () => isEditing ? setEditingMatchId(null) : startEditing(match) : undefined}>
              {isAdmin && match.status === 'draft' ? <div className="border-t border-slate-200 p-4 dark:border-slate-800"><button type="button" onClick={() => void publishMatch(match.match_id)} className="min-h-10 rounded-md bg-brand-500 px-3 text-sm font-semibold text-slate-950">Publish draft</button></div> : null}
              {canManageSelection && match.status === 'scheduled' ? <div className="border-t border-slate-200 p-4 dark:border-slate-800"><Link className="inline-flex min-h-10 items-center rounded-md border border-brand-500 px-3 py-2 text-sm font-semibold text-brand-800 dark:text-brand-300" to={`/matches/${match.match_id}/lineup?${new URLSearchParams({ ...(requestedSeason ? { season: requestedSeason } : {}), page: String(activePageIndex + 1) })}#match-${match.match_id}`}>{isAdmin ? 'Manage team lineups' : 'Select playing team'}</Link></div> : null}
              {match.status === 'scheduled' ? <div className="border-t border-slate-200 p-4 dark:border-slate-800"><Link className="inline-flex min-h-10 items-center rounded-md bg-brand-500 px-3 py-2 text-sm font-semibold text-slate-950" to={`/matches/${match.match_id}/live`}>Start live match</Link></div> : null}
              {match.status === 'live' || match.status === 'completed' ? <div className="flex flex-wrap gap-2 border-t border-slate-200 p-4 dark:border-slate-800">
                <Link className="inline-flex min-h-10 items-center rounded-md bg-brand-500 px-3 py-2 text-sm font-semibold text-slate-950" to={`/matches/${match.match_id}`}>{match.status === 'live' ? 'View live score' : 'View scorecard'}</Link>
                {match.status === 'live' ? <Link className="inline-flex min-h-10 items-center rounded-md border border-brand-500 px-3 py-2 text-sm font-semibold text-brand-800 dark:text-brand-300" to={`/matches/${match.match_id}/live`}>Open scorer</Link> : null}
              </div> : null}
              {isEditing ? <form className="border-t border-slate-200 p-4 dark:border-slate-800" onSubmit={(event) => { event.preventDefault(); void updateMatch(match.match_id); }}>
                <div className="grid gap-4 sm:grid-cols-2">
                  <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Home team<select required value={editingHomeTeamId} onChange={(event) => setEditingHomeTeamId(event.target.value)} className="form-select mt-1">{teams.map((team) => <option key={team.season_team_id} value={team.season_team_id}>{team.team_name}</option>)}</select></label>
                  <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Away team<select required value={editingAwayTeamId} onChange={(event) => setEditingAwayTeamId(event.target.value)} className="form-select mt-1">{teams.map((team) => <option key={team.season_team_id} value={team.season_team_id} disabled={team.season_team_id === editingHomeTeamId}>{team.team_name}</option>)}</select></label>
                  <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Date and time<input required type="datetime-local" value={editingMatchDate} onChange={(event) => setEditingMatchDate(event.target.value)} className="mt-1 block min-h-11 w-full rounded-md border border-slate-300 bg-white px-3 dark:border-slate-700 dark:bg-slate-950 dark:text-white" /></label>
                  <label className="text-sm font-medium text-slate-700 dark:text-slate-200">Venue<input disabled value={communityPark} className="mt-1 block min-h-11 w-full rounded-md border border-slate-300 bg-slate-100 px-3 text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300" /></label>
                </div>
                <div className="mt-4 flex flex-wrap gap-3"><button disabled={saving} type="submit" className="min-h-11 rounded-md bg-brand-500 px-4 text-sm font-semibold text-slate-950">Save changes</button><button disabled={saving} type="button" onClick={() => void deleteMatch(match.match_id)} className="min-h-11 rounded-md border border-red-300 px-4 text-sm font-semibold text-red-700 dark:border-red-900 dark:text-red-300">Delete match</button></div>
              </form> : null}
            </MatchCard>;
          })}</ul>
        </div>
        <MatchPagination pageCount={pageCount} currentPage={activePageIndex + 1} onPageChange={changePage} />
      </>)}
    </section>
  );
}
