create unique index if not exists season_team_managers_one_per_team_idx
  on public.season_team_managers (season_team_id);

create or replace function public.validate_season_team_manager()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_league_id uuid;
begin
  select s.league_id
  into target_league_id
  from public.season_teams st
  join public.seasons s on s.id = st.season_id
  where st.id = new.season_team_id;

  if target_league_id is null then
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

  if new.user_id is not null and not exists (
    select 1
    from public.league_members lm
    where lm.league_id = target_league_id
      and lm.user_id = new.user_id
      and lm.role = 'team_manager'
  ) then
    raise exception 'team manager user must have the team_manager role';
  end if;

  return new;
end;
$$;

drop trigger if exists season_team_managers_validate on public.season_team_managers;

create trigger season_team_managers_validate
before insert or update on public.season_team_managers
for each row execute function public.validate_season_team_manager();

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
    join public.season_teams st on st.id = stm.season_team_id
    join public.seasons s on s.id = st.season_id
    join public.league_members lm
      on lm.league_id = s.league_id
     and lm.user_id = stm.user_id
     and lm.role = 'team_manager'
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
  select exists (
    select 1
    from public.matches m
    where m.id = target_match_id
      and target_season_team_id in (m.home_season_team_id, m.away_season_team_id)
      and (
        public.has_league_role(public.league_id_for_match(m.id), array['admin'])
        or public.is_season_team_manager(target_season_team_id)
      )
  );
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
    st.id,
    t.id,
    t.name,
    stm.user_id,
    coalesce(
      nullif(au.raw_user_meta_data ->> 'name', ''),
      nullif(au.raw_user_meta_data ->> 'full_name', ''),
      nullif(btrim(stm.display_name), ''),
      au.email
    ),
    au.email,
    stm.player_id,
    manager_player.display_name,
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
    ),
    users
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
  target_league_id uuid;
  selected_player_name text;
begin
  select s.league_id
  into target_league_id
  from public.season_teams st
  join public.seasons s on s.id = st.season_id
  where st.id = target_season_team_id;

  if target_league_id is null then
    raise exception 'season team not found';
  end if;

  if not public.has_league_role(target_league_id, array['admin']) then
    raise exception 'only league admins can assign team managers';
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
    from public.league_members lm
    where lm.league_id = target_league_id
      and lm.user_id = target_user_id
      and lm.role = 'team_manager'
  ) then
    raise exception 'assigned user must have the team_manager role';
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

create or replace function public.get_match_team_selection_state(target_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
  target_league_id uuid;
  is_admin boolean;
  manager_team_ids uuid[];
  visible_teams jsonb;
begin
  select m.*
  into match_record
  from public.matches m
  where m.id = target_match_id;

  if match_record.id is null then
    raise exception 'match not found';
  end if;

  target_league_id := public.league_id_for_match(target_match_id);
  is_admin := public.has_league_role(target_league_id, array['admin']);

  select coalesce(array_agg(stm.season_team_id order by stm.season_team_id), '{}'::uuid[])
  into manager_team_ids
  from public.season_team_managers stm
  where stm.season_team_id in (match_record.home_season_team_id, match_record.away_season_team_id)
    and public.is_season_team_manager(stm.season_team_id);

  if not is_admin and cardinality(manager_team_ids) = 0 then
    raise exception 'only assigned team managers can view this match selection';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'season_team_id', st.id,
        'team_name', t.name,
        'editable', is_admin or st.id = any(manager_team_ids),
        'selected_roster_ids', coalesce(
          (
            select jsonb_agg(ml.season_roster_id order by ml.season_roster_id)
            from public.match_lineups ml
            where ml.match_id = target_match_id
              and ml.season_team_id = st.id
          ),
          '[]'::jsonb
        ),
        'players', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'season_roster_id', sr.id,
                'player_id', p.id,
                'display_name', p.display_name,
                'selected', exists (
                  select 1
                  from public.match_lineups ml
                  where ml.match_id = target_match_id
                    and ml.season_roster_id = sr.id
                )
              )
              order by p.display_name
            )
            from public.season_rosters sr
            join public.players p on p.id = sr.player_id
            where sr.season_team_id = st.id
          ),
          '[]'::jsonb
        )
      )
      order by case when st.id = match_record.home_season_team_id then 0 else 1 end
    ),
    '[]'::jsonb
  )
  into visible_teams
  from public.season_teams st
  join public.teams t on t.id = st.team_id
  where st.id in (match_record.home_season_team_id, match_record.away_season_team_id)
    and (is_admin or st.id = any(manager_team_ids));

  return jsonb_build_object(
    'match', jsonb_build_object(
      'id', match_record.id,
      'season_id', match_record.season_id,
      'status', match_record.status,
      'match_date', match_record.match_date,
      'venue', match_record.venue,
      'home_season_team_id', match_record.home_season_team_id,
      'away_season_team_id', match_record.away_season_team_id
    ),
    'min_players', (
      select s.match_min_players
      from public.seasons s
      where s.id = match_record.season_id
    ),
    'max_players', (
      select s.match_max_players
      from public.seasons s
      where s.id = match_record.season_id
    ),
    'is_admin', is_admin,
    'editable_season_team_id', case when is_admin then null else manager_team_ids[1] end,
    'teams', visible_teams
  );
end;
$$;

create or replace function public.save_match_team_lineup(
  target_match_id uuid,
  target_season_team_id uuid,
  target_season_roster_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
  target_league_id uuid;
  min_players integer;
  max_players integer;
  selected_ids uuid[] := coalesce(target_season_roster_ids, '{}'::uuid[]);
  selected_count integer;
  distinct_count integer;
  preserved_captain_id uuid;
begin
  select m.*
  into match_record
  from public.matches m
  where m.id = target_match_id
  for update;

  if match_record.id is null then
    raise exception 'match not found';
  end if;

  if target_season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id) then
    raise exception 'lineup team must be one of the match teams';
  end if;

  target_league_id := public.league_id_for_match(target_match_id);

  if not public.has_league_role(target_league_id, array['admin'])
    and not public.is_season_team_manager(target_season_team_id) then
    raise exception 'only league admins or the assigned team manager can save this lineup';
  end if;

  if match_record.status <> 'scheduled' then
    raise exception 'lineups can only be changed while the match is scheduled';
  end if;

  select s.match_min_players, s.match_max_players
  into min_players, max_players
  from public.seasons s
  where s.id = match_record.season_id;

  selected_count := cardinality(selected_ids);

  select count(distinct selected_id)::integer
  into distinct_count
  from unnest(selected_ids) as selected(selected_id);

  if selected_count <> distinct_count then
    raise exception 'a lineup cannot contain duplicate players';
  end if;

  if selected_count not between min_players and max_players then
    raise exception 'lineup must contain between % and % players', min_players, max_players;
  end if;

  if exists (
    select 1
    from unnest(selected_ids) as selected(selected_id)
    where not exists (
      select 1
      from public.season_rosters sr
      where sr.id = selected.selected_id
        and sr.season_team_id = target_season_team_id
        and sr.season_id = match_record.season_id
    )
  ) then
    raise exception 'every lineup player must belong to the selected team roster';
  end if;

  select ml.season_roster_id
  into preserved_captain_id
  from public.match_lineups ml
  where ml.match_id = target_match_id
    and ml.season_team_id = target_season_team_id
    and ml.is_captain
  limit 1;

  delete from public.match_lineups
  where match_id = target_match_id
    and season_team_id = target_season_team_id;

  insert into public.match_lineups (
    match_id,
    season_team_id,
    season_roster_id,
    is_captain,
    selected_by_user_id
  )
  select
    target_match_id,
    target_season_team_id,
    sr.id,
    sr.id = preserved_captain_id,
    auth.uid()
  from public.season_rosters sr
  where sr.id = any(selected_ids);

  return jsonb_build_object(
    'match_id', target_match_id,
    'season_team_id', target_season_team_id,
    'selected_count', selected_count
  );
end;
$$;

grant execute on function public.is_season_team_manager(uuid) to authenticated;
grant execute on function public.can_manage_match_lineup(uuid, uuid) to authenticated;
grant execute on function public.get_team_manager_assignments(uuid) to authenticated;
grant execute on function public.set_season_team_manager(uuid, uuid, uuid) to authenticated;
grant execute on function public.get_match_team_selection_state(uuid) to authenticated;
grant execute on function public.save_match_team_lineup(uuid, uuid, uuid[]) to authenticated;

revoke insert, update, delete on public.season_team_managers from authenticated;
revoke insert, update, delete on public.match_lineups from authenticated;

drop policy if exists "league members can read match lineups" on public.match_lineups;
drop policy if exists "league admins scorers and managers can manage match lineups" on public.match_lineups;
drop policy if exists "league admins can manage match lineups" on public.match_lineups;

create policy "authorized users can read match lineups"
on public.match_lineups
for select
using (
  public.has_league_role(public.league_id_for_match(match_id), array['admin'])
  or public.is_season_team_manager(season_team_id)
  or (
    exists (
      select 1
      from public.matches m
      where m.id = match_lineups.match_id
        and m.status in ('live', 'completed')
    )
    and public.is_league_member(public.league_id_for_match(match_id))
  )
);

create policy "admins and assigned managers can insert scheduled match lineups"
on public.match_lineups
for insert
with check (
  public.can_manage_match_lineup(match_id, season_team_id)
  and exists (
    select 1
    from public.matches m
    where m.id = match_lineups.match_id
      and m.status = 'scheduled'
  )
);

create policy "admins and assigned managers can update scheduled match lineups"
on public.match_lineups
for update
using (
  public.can_manage_match_lineup(match_id, season_team_id)
  and exists (
    select 1
    from public.matches m
    where m.id = match_lineups.match_id
      and m.status = 'scheduled'
  )
)
with check (
  public.can_manage_match_lineup(match_id, season_team_id)
  and exists (
    select 1
    from public.matches m
    where m.id = match_lineups.match_id
      and m.status = 'scheduled'
  )
);

create policy "admins and assigned managers can delete scheduled match lineups"
on public.match_lineups
for delete
using (
  public.can_manage_match_lineup(match_id, season_team_id)
  and exists (
    select 1
    from public.matches m
    where m.id = match_lineups.match_id
      and m.status = 'scheduled'
  )
);
