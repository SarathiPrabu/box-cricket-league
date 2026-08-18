-- Verifies a six-player historical match can be scored with only five batters
-- in each innings while normal six-over and one-over-per-bowler rules remain.

begin;

do $$
declare
  league_id_value uuid;
  season_id_value uuid;
  home_team_id uuid;
  away_team_id uuid;
  home_season_team_id uuid;
  away_season_team_id uuid;
  match_id_value uuid;
  player_id_value uuid;
  roster_id_value uuid;
  lineup_id_value uuid;
  first_innings_id uuid;
  second_innings_id uuid;
  over_assignment_id uuid;
  final_result jsonb;
  home_rosters uuid[] := array[]::uuid[];
  away_rosters uuid[] := array[]::uuid[];
  home_lineups uuid[] := array[]::uuid[];
  i integer;
  j integer;
begin
  insert into public.leagues (name, slug)
  values ('Historical incomplete batting test', 'historical-incomplete-' || replace(extensions.gen_random_uuid()::text, '-', ''))
  returning id into league_id_value;

  insert into public.seasons (
    league_id,
    name,
    players_per_team,
    match_min_players,
    match_max_players,
    balls_per_over,
    max_overs_per_player
  ) values (
    league_id_value,
    'Historical exception test season',
    6,
    6,
    6,
    6,
    1
  ) returning id into season_id_value;

  insert into public.teams (league_id, name, slug)
  values (league_id_value, 'Historical Jersey Indians', 'historical-jersey-indians')
  returning id into home_team_id;

  insert into public.teams (league_id, name, slug)
  values (league_id_value, 'Historical Dhurandhars United', 'historical-dhurandhars-united')
  returning id into away_team_id;

  insert into public.season_teams (season_id, team_id)
  values (season_id_value, home_team_id)
  returning id into home_season_team_id;

  insert into public.season_teams (season_id, team_id)
  values (season_id_value, away_team_id)
  returning id into away_season_team_id;

  insert into public.matches (
    season_id,
    home_season_team_id,
    away_season_team_id,
    status
  ) values (
    season_id_value,
    home_season_team_id,
    away_season_team_id,
    'scheduled'
  ) returning id into match_id_value;

  for i in 1..12 loop
    insert into public.players (display_name)
    values ('Historical test player ' || i)
    returning id into player_id_value;

    if i <= 6 then
      insert into public.season_rosters (season_team_id, season_id, player_id)
      values (home_season_team_id, season_id_value, player_id_value)
      returning id into roster_id_value;
      home_rosters := array_append(home_rosters, roster_id_value);
      insert into public.match_lineups (match_id, season_team_id, season_roster_id, is_captain)
      values (match_id_value, home_season_team_id, roster_id_value, i = 1)
      returning id into lineup_id_value;
      home_lineups := array_append(home_lineups, lineup_id_value);
    else
      insert into public.season_rosters (season_team_id, season_id, player_id)
      values (away_season_team_id, season_id_value, player_id_value)
      returning id into roster_id_value;
      away_rosters := array_append(away_rosters, roster_id_value);
      insert into public.match_lineups (match_id, season_team_id, season_roster_id, is_captain)
      values (match_id_value, away_season_team_id, roster_id_value, i = 7);
    end if;
  end loop;

  if public.set_match_historical_batting_exception(match_id_value, true) is distinct from true then
    raise exception 'historical batting exception was not enabled';
  end if;

  first_innings_id := public.start_match(match_id_value, home_season_team_id);

  for i in 1..5 loop
    over_assignment_id := public.set_match_over_assignment(
      first_innings_id,
      i,
      away_rosters[i],
      away_rosters[6]
    );
    perform public.select_match_batter(first_innings_id, home_rosters[i]);
    for j in 1..6 loop
      perform public.record_match_delivery(
        over_assignment_id,
        home_rosters[i],
        null,
        'legal',
        1,
        0,
        false,
        null,
        null,
        null
      );
    end loop;
    perform public.confirm_match_over(over_assignment_id);
  end loop;

  -- The fifth real batter continues in flexible mode; the sixth lineup player
  -- never receives a batting turn.
  over_assignment_id := public.set_match_over_assignment(
    first_innings_id,
    6,
    away_rosters[6],
    away_rosters[5]
  );
  perform public.select_match_batter(first_innings_id, home_rosters[5]);
  for j in 1..6 loop
    perform public.record_match_delivery(
      over_assignment_id,
      home_rosters[5],
      null,
      'legal',
      1,
      0,
      false,
      null,
      null,
      null
    );
  end loop;
  perform public.confirm_match_over(over_assignment_id);

  second_innings_id := public.complete_match_innings(first_innings_id);

  for i in 1..5 loop
    over_assignment_id := public.set_match_over_assignment(
      second_innings_id,
      i,
      home_rosters[i],
      home_rosters[6]
    );
    perform public.select_match_batter(second_innings_id, away_rosters[i]);
    for j in 1..6 loop
      perform public.record_match_delivery(
        over_assignment_id,
        away_rosters[i],
        null,
        'legal',
        0,
        0,
        false,
        null,
        null,
        null
      );
    end loop;
    perform public.confirm_match_over(over_assignment_id);
  end loop;

  over_assignment_id := public.set_match_over_assignment(
    second_innings_id,
    6,
    home_rosters[6],
    home_rosters[5]
  );
  perform public.select_match_batter(second_innings_id, away_rosters[5]);
  for j in 1..6 loop
    perform public.record_match_delivery(
      over_assignment_id,
      away_rosters[5],
      null,
      'legal',
      0,
      0,
      false,
      null,
      null,
      null
    );
  end loop;
  perform public.confirm_match_over(over_assignment_id);

  if public.complete_match_innings(second_innings_id) is not null then
    raise exception 'second innings completion returned an unexpected innings';
  end if;

  select public.finalize_match(match_id_value, home_lineups[1]) into final_result;

  if final_result ->> 'result_type' is distinct from 'win'
    or (final_result ->> 'winner_season_team_id')::uuid is distinct from home_season_team_id
    or (final_result ->> 'first_score')::integer is distinct from 36
    or (final_result ->> 'second_score')::integer is distinct from 0 then
    raise exception 'unexpected historical result: %', final_result;
  end if;

  if (
    select count(*)
    from public.match_batting_turns mbt
    where mbt.innings_id = first_innings_id
      and mbt.phase = 'initial'
  ) <> 5
  or exists (
    select 1
    from public.match_batting_turns mbt
    where mbt.innings_id = first_innings_id
      and mbt.batter_season_roster_id = home_rosters[6]
  ) then
    raise exception 'historical innings did not preserve exactly five batting players';
  end if;

  if (
    select total_runs from public.match_innings where id = first_innings_id
  ) <> 36
  or (
    select total_runs from public.match_innings where id = second_innings_id
  ) <> 0 then
    raise exception 'historical innings totals were not persisted';
  end if;
end;
$$;

rollback;
