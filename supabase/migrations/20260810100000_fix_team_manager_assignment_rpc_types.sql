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

  if not public.has_league_role(target_league_id, array['admin']) then
    raise exception 'only league admins can view team manager assignments';
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
  from public.league_members lm
  join auth.users au on au.id = lm.user_id
  where lm.league_id = target_league_id
    and lm.role = 'team_manager';

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

grant execute on function public.get_team_manager_assignments(uuid) to authenticated;
