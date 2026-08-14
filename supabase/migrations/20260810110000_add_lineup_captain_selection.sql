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
        'captain_roster_id', (
          select ml.season_roster_id
          from public.match_lineups ml
          where ml.match_id = target_match_id
            and ml.season_team_id = st.id
            and ml.is_captain
          limit 1
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

drop function if exists public.save_match_team_lineup(uuid, uuid, uuid[]);

create function public.save_match_team_lineup(
  target_match_id uuid,
  target_season_team_id uuid,
  target_season_roster_ids uuid[],
  target_captain_season_roster_id uuid
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

  if not exists (
    select 1
    from unnest(selected_ids) as selected(selected_id)
    where selected.selected_id = target_captain_season_roster_id
  ) then
    raise exception 'captain must be one of the selected lineup players';
  end if;

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
    sr.id = target_captain_season_roster_id,
    auth.uid()
  from public.season_rosters sr
  where sr.id = any(selected_ids);

  return jsonb_build_object(
    'match_id', target_match_id,
    'season_team_id', target_season_team_id,
    'captain_season_roster_id', target_captain_season_roster_id,
    'selected_count', selected_count
  );
end;
$$;

grant execute on function public.get_match_team_selection_state(uuid) to authenticated;
grant execute on function public.save_match_team_lineup(uuid, uuid, uuid[], uuid) to authenticated;
