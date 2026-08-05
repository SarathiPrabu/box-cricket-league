alter table public.league_members
  drop constraint if exists league_members_role_check,
  add constraint league_members_role_check
  check (role in ('admin', 'scorer', 'player', 'team_manager'));

create or replace function public.is_season_team_manager(target_season_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.season_team_managers stm
    where stm.season_team_id = target_season_team_id
      and stm.user_id = auth.uid()
  );
$$;

create or replace function public.can_manage_match_lineup(
  target_match_id uuid,
  target_season_team_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_league_role(
    public.league_id_for_match(target_match_id),
    array['admin', 'scorer']
  )
  or public.is_season_team_manager(target_season_team_id);
$$;

create or replace function public.get_my_league_roles()
returns table (
  league_id uuid,
  league_slug text,
  league_name text,
  role text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.id as league_id,
    l.slug as league_slug,
    l.name as league_name,
    lm.role
  from public.league_members lm
  join public.leagues l on l.id = lm.league_id
  where lm.user_id = auth.uid()
  order by l.name, lm.role;
$$;

grant execute on function public.is_season_team_manager(uuid) to authenticated;
grant execute on function public.can_manage_match_lineup(uuid, uuid) to authenticated;
grant execute on function public.get_my_league_roles() to authenticated;

drop policy if exists "league admins can manage matches" on public.matches;

create policy "league admins and scorers can manage matches"
on public.matches
for all
using (
  public.has_league_role(
    public.league_id_for_match(id),
    array['admin', 'scorer']
  )
)
with check (
  exists (
    select 1
    from public.seasons s
    where s.id = matches.season_id
      and public.has_league_role(s.league_id, array['admin', 'scorer'])
  )
);

drop policy if exists "league admins can manage match staff" on public.match_staff;

create policy "league admins and scorers can manage match staff"
on public.match_staff
for all
using (
  public.has_league_role(
    public.league_id_for_match(match_id),
    array['admin', 'scorer']
  )
)
with check (
  public.has_league_role(
    public.league_id_for_match(match_id),
    array['admin', 'scorer']
  )
);

drop policy if exists "league admins can manage match lineups" on public.match_lineups;

create policy "league admins scorers and managers can manage match lineups"
on public.match_lineups
for all
using (public.can_manage_match_lineup(match_id, season_team_id))
with check (public.can_manage_match_lineup(match_id, season_team_id));

drop policy if exists "league admins can manage match player stats" on public.match_player_stats;

create policy "league admins and scorers can manage match player stats"
on public.match_player_stats
for all
using (
  public.has_league_role(
    public.league_id_for_match_lineup(match_lineup_id),
    array['admin', 'scorer']
  )
)
with check (
  public.has_league_role(
    public.league_id_for_match_lineup(match_lineup_id),
    array['admin', 'scorer']
  )
);
