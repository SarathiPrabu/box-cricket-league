-- Temporary test mode: remove role-based access checks without removing the
-- role data or the domain-integrity rules enforced by the database.

create or replace function public.is_league_member(target_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select true;
$$;

create or replace function public.has_league_role(target_league_id uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select true;
$$;

create or replace function public.validate_season_team_manager()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.season_teams st
    where st.id = new.season_team_id
  ) then
    raise exception 'season team not found';
  end if;

  if new.player_id is not null and not exists (
    select 1
    from public.season_rosters sr
    where sr.season_team_id = new.season_team_id
      and sr.player_id = new.player_id
  ) then
    raise exception 'team manager player must belong to the season team roster';
  end if;

  return new;
end;
$$;

create or replace function public.get_team_manager_assignments(target_season_id uuid)
returns table (
  season_team_id uuid,
  team_id uuid,
  team_name text,
  manager_user_id uuid,
  manager_user_name text,
  manager_user_email text,
  manager_player_id uuid,
  manager_player_name text,
  roster jsonb,
  eligible_users jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target_league_id uuid;
  users jsonb;
begin
  select s.league_id
  into target_league_id
  from public.seasons s
  where s.id = target_season_id;

  if target_league_id is null then
    raise exception 'season not found';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', au.id,
        'display_name', coalesce(
          nullif(au.raw_user_meta_data ->> 'name', ''),
          nullif(au.raw_user_meta_data ->> 'full_name', ''),
          au.email
        ),
        'email', au.email
      )
      order by coalesce(
        nullif(au.raw_user_meta_data ->> 'name', ''),
        nullif(au.raw_user_meta_data ->> 'full_name', ''),
        au.email
      ), au.email
    ),
    '[]'::jsonb
  )
  into users
  from auth.users au;

  return query
  select
    st.id::uuid,
    t.id::uuid,
    t.name::text,
    stm.user_id::uuid,
    coalesce(
      nullif(au.raw_user_meta_data ->> 'name', ''),
      nullif(au.raw_user_meta_data ->> 'full_name', ''),
      nullif(btrim(stm.display_name), ''),
      au.email
    )::text,
    au.email::text,
    stm.player_id::uuid,
    manager_player.display_name::text,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'season_roster_id', sr.id,
            'player_id', p.id,
            'display_name', p.display_name
          )
          order by p.display_name
        )
        from public.season_rosters sr
        join public.players p on p.id = sr.player_id
        where sr.season_team_id = st.id
      ),
      '[]'::jsonb
    )::jsonb,
    users::jsonb
  from public.season_teams st
  join public.teams t on t.id = st.team_id
  left join public.season_team_managers stm on stm.season_team_id = st.id
  left join auth.users au on au.id = stm.user_id
  left join public.players manager_player on manager_player.id = stm.player_id
  where st.season_id = target_season_id
  order by t.name;
end;
$$;

create or replace function public.set_season_team_manager(
  target_season_team_id uuid,
  target_user_id uuid,
  target_player_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_player_name text;
begin
  if not exists (
    select 1
    from public.season_teams st
    where st.id = target_season_team_id
  ) then
    raise exception 'season team not found';
  end if;

  if target_user_id is null and target_player_id is null then
    delete from public.season_team_managers
    where season_team_id = target_season_team_id;
    return;
  end if;

  if target_user_id is null or target_player_id is null then
    raise exception 'manager user and player must be assigned together';
  end if;

  if not exists (
    select 1
    from auth.users au
    where au.id = target_user_id
  ) then
    raise exception 'manager user not found';
  end if;

  select p.display_name
  into selected_player_name
  from public.season_rosters sr
  join public.players p on p.id = sr.player_id
  where sr.season_team_id = target_season_team_id
    and sr.player_id = target_player_id;

  if selected_player_name is null then
    raise exception 'manager player must belong to the season team roster';
  end if;

  delete from public.season_team_managers
  where season_team_id = target_season_team_id;

  insert into public.season_team_managers (
    season_team_id,
    player_id,
    user_id,
    display_name
  ) values (
    target_season_team_id,
    target_player_id,
    target_user_id,
    selected_player_name
  );
end;
$$;

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on public.leagues,
  public.league_members,
  public.players,
  public.teams,
  public.seasons,
  public.season_teams,
  public.season_team_managers,
  public.season_rosters,
  public.matches,
  public.match_staff,
  public.match_lineups,
  public.match_player_stats,
  public.match_innings,
  public.match_over_assignments,
  public.match_deliveries,
  public.match_batting_turns
to anon, authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'leagues',
    'league_members',
    'players',
    'teams',
    'seasons',
    'season_teams',
    'season_team_managers',
    'season_rosters',
    'matches',
    'match_staff',
    'match_lineups',
    'match_player_stats',
    'match_innings',
    'match_over_assignments',
    'match_deliveries',
    'match_batting_turns'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'temporary unrestricted test access', table_name);
    execute format(
      'create policy %I on public.%I for all to anon, authenticated using (true) with check (true)',
      'temporary unrestricted test access',
      table_name
    );
  end loop;
end;
$$;

grant execute on function public.get_my_league_roles() to anon, authenticated;
grant execute on function public.get_league_role_assignments(text) to anon, authenticated;
grant execute on function public.set_league_member_roles(text, uuid, text[]) to anon, authenticated;
grant execute on function public.get_team_manager_assignments(uuid) to anon, authenticated;
grant execute on function public.set_season_team_manager(uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.get_match_team_selection_state(uuid) to anon, authenticated;
grant execute on function public.save_match_team_lineup(uuid, uuid, uuid[], uuid) to anon, authenticated;
grant execute on function public.is_season_team_manager(uuid) to anon, authenticated;
grant execute on function public.can_manage_match_lineup(uuid, uuid) to anon, authenticated;
