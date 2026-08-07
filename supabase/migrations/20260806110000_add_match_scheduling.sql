alter table public.matches
  alter column venue set default 'Community Park';

alter table public.matches
  drop constraint if exists matches_status_check,
  add constraint matches_status_check
    check (status in ('draft', 'scheduled', 'live', 'completed', 'cancelled'));

-- Scheduling is an admin action. Scorers receive match-specific live-scoring
-- permissions in the later scoring slice.
drop policy if exists "league admins and scorers can manage matches" on public.matches;

create policy "league admins can manage matches"
on public.matches
for all
using (public.has_league_role(public.league_id_for_match(id), array['admin']))
with check (
  exists (
    select 1
    from public.seasons s
    where s.id = matches.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
);

create or replace function public.get_public_matches_for_season(target_season_id uuid)
returns table (
  match_id uuid,
  season_id uuid,
  home_season_team_id uuid,
  home_team_name text,
  away_season_team_id uuid,
  away_team_name text,
  match_date timestamptz,
  venue text,
  status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id,
    m.season_id,
    m.home_season_team_id,
    home_team.name,
    m.away_season_team_id,
    away_team.name,
    m.match_date,
    m.venue,
    m.status
  from public.matches m
  join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
  join public.teams home_team on home_team.id = home_season_team.team_id
  join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
  join public.teams away_team on away_team.id = away_season_team.team_id
  join public.seasons s on s.id = m.season_id
  where m.season_id = target_season_id
    and (
      m.status <> 'draft'
      or public.has_league_role(s.league_id, array['admin'])
    )
  order by m.match_date asc nulls last, home_team.name, away_team.name;
$$;

grant execute on function public.get_public_matches_for_season(uuid) to anon, authenticated;
