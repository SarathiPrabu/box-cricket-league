-- Exercises a complete 5-player vs 6-player match through the scoring RPCs.
-- Every test row is rolled back, including finalized player stats and standings.

begin;

create temporary table bcl_5v6_test_result (
  match_id uuid not null,
  season_id uuid not null,
  five_player_season_team_id uuid not null,
  six_player_season_team_id uuid not null,
  first_innings_id uuid not null,
  second_innings_id uuid not null
) on commit drop;

do $$
declare
  test_suffix text := replace(extensions.gen_random_uuid()::text, '-', '');
  league_id_value uuid;
  season_id_value uuid;
  five_player_team_id uuid;
  six_player_team_id uuid;
  five_player_season_team_id uuid;
  six_player_season_team_id uuid;
  match_id_value uuid;
  player_id_value uuid;
  roster_id_value uuid;
  lineup_id_value uuid;
  first_innings_id uuid;
  second_innings_id uuid;
  next_innings_id uuid;
  over_assignment_id uuid;
  first_delivery_id uuid;
  wicketkeeper_roster_id uuid;
  final_result jsonb;
  scoring_state jsonb;
  five_player_rosters uuid[] := array[]::uuid[];
  six_player_rosters uuid[] := array[]::uuid[];
  five_player_lineups uuid[] := array[]::uuid[];
  six_player_lineups uuid[] := array[]::uuid[];
  legal_ball_count integer;
  score_value integer;
  wicket_count integer;
  turn_count integer;
  flexible_ball_count integer;
  stats_count integer;
  points_value bigint;
  wins_value bigint;
  losses_value bigint;
  confirmed_over_locked boolean := false;
  confirmed_keeper_change_locked boolean := false;
  i integer;
  j integer;
begin
  if to_regclass('public.match_batting_turns') is null
    or to_regprocedure('public.select_match_batter(uuid,uuid)') is null
    or to_regprocedure('public.change_current_over_wicketkeeper(uuid,uuid)') is null then
    raise exception 'batting-turn migration objects are missing';
  end if;

  if (
    select is_nullable
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_deliveries'
      and column_name = 'non_striker_season_roster_id'
  ) is distinct from 'YES' then
    raise exception 'non-striker column must be nullable';
  end if;

  insert into public.leagues (name, slug)
  values ('Codex 5v6 transactional test', 'codex-5v6-' || test_suffix)
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
    'Transactional test season',
    6,
    5,
    6,
    6,
    1
  ) returning id into season_id_value;

  insert into public.teams (league_id, name, slug)
  values (league_id_value, 'Five Player Test Team', 'five-player-test-team')
  returning id into five_player_team_id;

  insert into public.teams (league_id, name, slug)
  values (league_id_value, 'Six Player Test Team', 'six-player-test-team')
  returning id into six_player_team_id;

  insert into public.season_teams (season_id, team_id)
  values (season_id_value, five_player_team_id)
  returning id into five_player_season_team_id;

  insert into public.season_teams (season_id, team_id)
  values (season_id_value, six_player_team_id)
  returning id into six_player_season_team_id;

  insert into public.matches (
    season_id,
    home_season_team_id,
    away_season_team_id,
    match_date,
    venue,
    status
  ) values (
    season_id_value,
    five_player_season_team_id,
    six_player_season_team_id,
    now(),
    'Transactional test venue',
    'scheduled'
  ) returning id into match_id_value;

  for i in 1..11 loop
    insert into public.players (display_name)
    values ('Codex 5v6 Test Player ' || i)
    returning id into player_id_value;

    if i <= 5 then
      insert into public.season_rosters (season_team_id, season_id, player_id)
      values (five_player_season_team_id, season_id_value, player_id_value)
      returning id into roster_id_value;

      five_player_rosters := array_append(five_player_rosters, roster_id_value);

      insert into public.match_lineups (
        match_id,
        season_team_id,
        season_roster_id,
        is_captain
      ) values (
        match_id_value,
        five_player_season_team_id,
        roster_id_value,
        i = 1
      ) returning id into lineup_id_value;

      five_player_lineups := array_append(five_player_lineups, lineup_id_value);
    else
      insert into public.season_rosters (season_team_id, season_id, player_id)
      values (six_player_season_team_id, season_id_value, player_id_value)
      returning id into roster_id_value;

      six_player_rosters := array_append(six_player_rosters, roster_id_value);

      insert into public.match_lineups (
        match_id,
        season_team_id,
        season_roster_id,
        is_captain
      ) values (
        match_id_value,
        six_player_season_team_id,
        roster_id_value,
        i = 6
      ) returning id into lineup_id_value;

      six_player_lineups := array_append(six_player_lineups, lineup_id_value);
    end if;
  end loop;

  -- Six-player team bats first. The five-player lineup sets a 5-over limit.
  first_innings_id := public.start_match(match_id_value, six_player_season_team_id);

  if not exists (
    select 1
    from public.match_innings mi
    where mi.id = first_innings_id
      and mi.overs_limit = 5
      and mi.legal_balls_limit = 30
  ) then
    raise exception '5v6 match did not start with a 5-over, 30-ball innings';
  end if;

  -- Over 1: four batters are dismissed first ball. Batter 5 faces two balls.
  over_assignment_id := public.set_match_over_assignment(
    first_innings_id,
    1,
    five_player_rosters[1],
    five_player_rosters[2]
  );

  for i in 1..4 loop
    perform public.select_match_batter(first_innings_id, six_player_rosters[i]);

    if i = 1 then
      begin
        perform public.record_match_delivery(
          over_assignment_id,
          six_player_rosters[i],
          null,
          'legal',
          0,
          0,
          true,
          six_player_rosters[i],
          'run_out',
          five_player_rosters[3]
        );
        raise exception 'run out dismissal remained available';
      exception
        when others then
          if sqlerrm <> 'run out is no longer supported' then
            raise;
          end if;
      end;
    end if;

    roster_id_value := public.record_match_delivery(
      over_assignment_id,
      six_player_rosters[i],
      null,
      'legal',
      0,
      0,
      true,
      six_player_rosters[i],
      case when i = 1 then 'hit_out_of_field' else 'bowled' end,
      null
    );

    if i = 1 then
      first_delivery_id := roster_id_value;

      perform public.change_current_over_wicketkeeper(
        over_assignment_id,
        five_player_rosters[3]
      );

      if not exists (
        select 1
        from public.match_over_assignments moa
        where moa.id = over_assignment_id
          and moa.bowler_season_roster_id = five_player_rosters[1]
          and moa.wicketkeeper_season_roster_id = five_player_rosters[3]
      ) then
        raise exception 'mid-over wicketkeeper change did not preserve the bowler';
      end if;
    end if;
  end loop;

  perform public.select_match_batter(first_innings_id, six_player_rosters[5]);
  for j in 1..2 loop
    perform public.record_match_delivery(
      over_assignment_id,
      six_player_rosters[5],
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

  -- A completed over remains editable until confirmation, including a delivery
  -- from an earlier batting turn in the same over.
  perform public.update_current_over_delivery(
    first_delivery_id,
    six_player_rosters[1],
    null,
    'legal',
    0,
    0,
    true,
    six_player_rosters[1],
    'hit_out_of_field',
    null
  );

  perform public.confirm_match_over(over_assignment_id);

  begin
    perform public.change_current_over_wicketkeeper(
      over_assignment_id,
      five_player_rosters[2]
    );
  exception
    when others then
      if sqlerrm = 'a confirmed over is locked' then
        confirmed_keeper_change_locked := true;
      else
        raise;
      end if;
  end;

  if not confirmed_keeper_change_locked then
    raise exception 'confirmed over wicketkeeper remained editable';
  end if;

  begin
    perform public.update_current_over_delivery(
      first_delivery_id,
      six_player_rosters[1],
      null,
      'legal',
      0,
      0,
      true,
      six_player_rosters[1],
      'hit_out_of_field',
      null
    );
  exception
    when others then
      if sqlerrm = 'a confirmed over is locked' then
        confirmed_over_locked := true;
      else
        raise;
      end if;
  end;

  if not confirmed_over_locked then
    raise exception 'confirmed over remained editable';
  end if;

  -- Over 2: batter 5 completes six legal balls; batter 6 starts their turn.
  over_assignment_id := public.set_match_over_assignment(
    first_innings_id,
    2,
    five_player_rosters[2],
    five_player_rosters[3]
  );

  for j in 1..4 loop
    perform public.record_match_delivery(
      over_assignment_id,
      six_player_rosters[5],
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

  perform public.select_match_batter(first_innings_id, six_player_rosters[6]);
  for j in 1..2 loop
    perform public.record_match_delivery(
      over_assignment_id,
      six_player_rosters[6],
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

  -- Over 3: batter 6 completes their turn. All six initial turns are now done,
  -- so batter 5 is selected again for the preserved-ball phase.
  over_assignment_id := public.set_match_over_assignment(
    first_innings_id,
    3,
    five_player_rosters[3],
    five_player_rosters[4]
  );

  for j in 1..4 loop
    perform public.record_match_delivery(
      over_assignment_id,
      six_player_rosters[6],
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

  select count(*)::integer
  into turn_count
  from public.match_batting_turns mbt
  where mbt.innings_id = first_innings_id
    and mbt.phase = 'initial';

  if turn_count <> 6 then
    raise exception 'all six players must receive an initial batting turn';
  end if;

  perform public.select_match_batter(first_innings_id, six_player_rosters[5]);

  if not exists (
    select 1
    from public.match_batting_turns mbt
    where mbt.innings_id = first_innings_id
      and mbt.batter_season_roster_id = six_player_rosters[5]
      and mbt.phase = 'flexible'
      and mbt.status = 'active'
  ) then
    raise exception 'preserved-ball phase did not open after all six initial turns';
  end if;

  for j in 1..2 loop
    perform public.record_match_delivery(
      over_assignment_id,
      six_player_rosters[5],
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

  -- Overs 4 and 5: the not-out batter faces all 12 remaining preserved balls.
  for i in 4..5 loop
    if i = 4 then
      wicketkeeper_roster_id := five_player_rosters[5];
    else
      wicketkeeper_roster_id := five_player_rosters[1];
    end if;

    over_assignment_id := public.set_match_over_assignment(
      first_innings_id,
      i,
      five_player_rosters[i],
      wicketkeeper_roster_id
    );

    for j in 1..6 loop
      perform public.record_match_delivery(
        over_assignment_id,
        six_player_rosters[5],
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

  select
    count(*) filter (where md.delivery_type = 'legal')::integer,
    coalesce(sum(md.batter_runs + md.extra_runs), 0)::integer,
    count(*) filter (where md.is_wicket)::integer
  into legal_ball_count, score_value, wicket_count
  from public.match_deliveries md
  where md.innings_id = first_innings_id;

  if legal_ball_count <> 30 or score_value <> 26 or wicket_count <> 4 then
    raise exception 'unexpected first innings: legal balls %, score %, wickets %',
      legal_ball_count,
      score_value,
      wicket_count;
  end if;

  second_innings_id := public.complete_match_innings(first_innings_id);

  -- Five-player chase: every batter faces exactly six legal balls. Five of the
  -- six-player lineup bowl one over each; player 6 does not bowl.
  for i in 1..5 loop
    over_assignment_id := public.set_match_over_assignment(
      second_innings_id,
      i,
      six_player_rosters[i],
      six_player_rosters[6]
    );

    perform public.select_match_batter(second_innings_id, five_player_rosters[i]);

    for j in 1..6 loop
      perform public.record_match_delivery(
        over_assignment_id,
        five_player_rosters[i],
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

  next_innings_id := public.complete_match_innings(second_innings_id);
  if next_innings_id is not null then
    raise exception 'second innings completion must not create another innings';
  end if;

  final_result := public.finalize_match(match_id_value, six_player_lineups[5]);

  if final_result ->> 'result_type' is distinct from 'win'
    or (final_result ->> 'winner_season_team_id')::uuid is distinct from six_player_season_team_id
    or (final_result ->> 'first_score')::integer is distinct from 26
    or (final_result ->> 'second_score')::integer is distinct from 0 then
    raise exception 'unexpected finalized result: %', final_result;
  end if;

  select count(*)::integer
  into stats_count
  from public.match_player_stats mps
  join public.match_lineups ml on ml.id = mps.match_lineup_id
  where ml.match_id = match_id_value;

  if stats_count <> 11 then
    raise exception 'finalization must create stats for all 11 players';
  end if;

  if not exists (
    select 1
    from public.match_player_stats mps
    where mps.match_lineup_id = six_player_lineups[5]
      and mps.runs = 20
      and mps.balls_faced = 20
      and mps.is_player_of_match
  ) then
    raise exception 'preserved-ball batter stats were not finalized correctly';
  end if;

  if not exists (
    select 1
    from public.match_player_stats mps
    where mps.match_lineup_id = six_player_lineups[6]
      and mps.runs = 6
      and mps.balls_faced = 6
      and mps.balls_bowled = 0
  ) then
    raise exception 'sixth-player batting/bowling stats were not finalized correctly';
  end if;

  if not exists (
    select 1
    from public.match_player_stats mps
    where mps.match_lineup_id = five_player_lineups[1]
      and mps.balls_faced = 6
      and mps.balls_bowled = 6
      and mps.wickets = 4
  ) then
    raise exception 'five-player bowling and wicket stats were not finalized correctly';
  end if;

  select coalesce(sum(turn_delivery_count.legal_balls), 0)::integer
  into flexible_ball_count
  from (
    select count(md.id) filter (where md.delivery_type = 'legal')::integer as legal_balls
    from public.match_batting_turns mbt
    left join public.match_deliveries md on md.batting_turn_id = mbt.id
    where mbt.innings_id = first_innings_id
      and mbt.phase = 'flexible'
    group by mbt.id
  ) turn_delivery_count;

  if flexible_ball_count <> 14 then
    raise exception 'expected 14 preserved balls, found %', flexible_ball_count;
  end if;

  select s.wins, s.points
  into wins_value, points_value
  from public.get_public_season_standings(season_id_value) s
  where s.season_team_id = six_player_season_team_id;

  if wins_value is distinct from 1 or points_value is distinct from 2 then
    raise exception 'winning team standings were not updated: wins %, points %', wins_value, points_value;
  end if;

  select s.losses
  into losses_value
  from public.get_public_season_standings(season_id_value) s
  where s.season_team_id = five_player_season_team_id;

  if losses_value is distinct from 1 then
    raise exception 'losing team standings were not updated';
  end if;

  scoring_state := public.get_match_scoring_state(match_id_value);
  if coalesce(jsonb_array_length(scoring_state -> 'innings'), -1) <> 2 then
    raise exception 'completed scoring state must contain two innings';
  end if;

  insert into bcl_5v6_test_result (
    match_id,
    season_id,
    five_player_season_team_id,
    six_player_season_team_id,
    first_innings_id,
    second_innings_id
  ) values (
    match_id_value,
    season_id_value,
    five_player_season_team_id,
    six_player_season_team_id,
    first_innings_id,
    second_innings_id
  );
end;
$$;

select jsonb_pretty(jsonb_build_object(
  'status', 'PASS',
  'format', '5v6',
  'overs_per_innings', 5,
  'legal_balls_per_innings', 30,
  'first_innings', '26/4',
  'early_dismissals', 4,
  'initial_turns_completed_or_dismissed', 6,
  'preserved_balls_faced', 14,
  'over_confirmation', 'editable before confirmation and locked afterward',
  'second_innings', '0/0',
  'winner_points', 2,
  'player_stats_rows', 11,
  'cleanup', 'all test data rolled back'
)) as verification_result
from bcl_5v6_test_result;

rollback;
