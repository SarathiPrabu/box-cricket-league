-- Correct the live Jersey Indians vs Titans first innings:
--   * Naveen bowled over 1 and Sumit bowled over 2.
--   * Paras was bowled by Arihant at 2.5.
--   * Manish then scored one run from Arihant at 2.6.
-- No other delivery result or run value is changed.

alter table public.match_over_assignments
  disable trigger match_over_assignments_validate;
alter table public.match_over_assignments
  disable trigger match_over_assignments_validate_lock;
alter table public.match_deliveries
  disable trigger match_deliveries_validate;
alter table public.match_deliveries
  disable trigger match_deliveries_prevent_confirmed_over_change;

do $correction$
declare
  target_match_id constant uuid := 'bd9f5c7d-69e3-4978-beab-cc5e49973ce9';
  target_innings_id constant uuid := '6d77134a-e086-4d81-b247-18101f98bdbc';
  expected_manish_turn_id constant uuid := '60a80b8b-19ef-4542-88e8-9d4ccad5dbe7';
  expected_manish_delivery_id constant uuid := '15f3c97b-8628-422e-99cc-bcbf22af0e23';
  target_match_status text;
  target_innings_status text;
  naveen_roster_id uuid;
  sumit_roster_id uuid;
  paras_roster_id uuid;
  manish_roster_id uuid;
  over_one_id uuid;
  over_two_id uuid;
  over_three_id uuid;
  over_one_bowler_id uuid;
  over_two_bowler_id uuid;
  arihant_roster_id uuid;
  paras_turn_id uuid := gen_random_uuid();
  paras_turn_started_at timestamptz;
  manish_turn_started_at timestamptz;
  manish_delivery_created_at timestamptz;
  manish_delivery_recorded_by uuid;
begin
  select m.status, mi.status
  into target_match_status, target_innings_status
  from public.matches m
  join public.match_innings mi
    on mi.match_id = m.id
   and mi.id = target_innings_id
   and mi.innings_number = 1
  join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
  join public.teams home_team on home_team.id = home_season_team.team_id
  join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
  join public.teams away_team on away_team.id = away_season_team.team_id
  where m.id = target_match_id
    and home_team.name = 'Jersey Indians'
    and away_team.name = 'Titans';

  if target_match_status is null then
    raise exception 'target Jersey Indians vs Titans first innings not found';
  end if;

  select ml.season_roster_id
  into naveen_roster_id
  from public.match_lineups ml
  join public.match_innings mi on mi.match_id = ml.match_id and mi.id = target_innings_id
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  where ml.match_id = target_match_id
    and ml.season_team_id = mi.bowling_season_team_id
    and p.display_name = 'Naveen Amin';

  select ml.season_roster_id
  into sumit_roster_id
  from public.match_lineups ml
  join public.match_innings mi on mi.match_id = ml.match_id and mi.id = target_innings_id
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  where ml.match_id = target_match_id
    and ml.season_team_id = mi.bowling_season_team_id
    and p.display_name = 'Sumit Lole';

  select ml.season_roster_id
  into paras_roster_id
  from public.match_lineups ml
  join public.match_innings mi on mi.match_id = ml.match_id and mi.id = target_innings_id
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  where ml.match_id = target_match_id
    and ml.season_team_id = mi.batting_season_team_id
    and p.display_name = 'Paras Adhiya';

  select ml.season_roster_id
  into manish_roster_id
  from public.match_lineups ml
  join public.match_innings mi on mi.match_id = ml.match_id and mi.id = target_innings_id
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  where ml.match_id = target_match_id
    and ml.season_team_id = mi.batting_season_team_id
    and p.display_name = 'Manish Doijode';

  if naveen_roster_id is null
    or sumit_roster_id is null
    or paras_roster_id is null
    or manish_roster_id is null then
    raise exception 'required bowler or batter was not found in the target lineup';
  end if;

  select moa.id, moa.bowler_season_roster_id
  into over_one_id, over_one_bowler_id
  from public.match_over_assignments moa
  where moa.innings_id = target_innings_id
    and moa.over_number = 1;

  select moa.id, moa.bowler_season_roster_id
  into over_two_id, over_two_bowler_id
  from public.match_over_assignments moa
  where moa.innings_id = target_innings_id
    and moa.over_number = 2;

  select moa.id, moa.bowler_season_roster_id
  into over_three_id, arihant_roster_id
  from public.match_over_assignments moa
  join public.season_rosters sr on sr.id = moa.bowler_season_roster_id
  join public.players p on p.id = sr.player_id
  where moa.innings_id = target_innings_id
    and moa.over_number = 3
    and p.display_name = 'Arihant Jain';

  if over_one_id is null or over_two_id is null or over_three_id is null then
    raise exception 'the first three over assignments were not found as expected';
  end if;

  -- Allow the migration to be retried safely after the desired correction.
  if over_one_bowler_id = naveen_roster_id
    and over_two_bowler_id = sumit_roster_id
    and exists (
      select 1
      from public.match_deliveries md
      join public.match_batting_turns mbt on mbt.id = md.batting_turn_id
      where md.innings_id = target_innings_id
        and md.delivery_sequence = 17
        and md.over_assignment_id = over_three_id
        and md.legal_ball_number = 5
        and md.striker_season_roster_id = paras_roster_id
        and md.bowler_season_roster_id = arihant_roster_id
        and md.delivery_type = 'legal'
        and md.batter_runs = 0
        and md.extra_runs = 0
        and md.is_wicket
        and md.dismissed_season_roster_id = paras_roster_id
        and md.dismissal_type = 'bowled'
        and mbt.batter_season_roster_id = paras_roster_id
        and mbt.turn_number = 4
        and mbt.status = 'ended'
        and mbt.end_reason = 'dismissed'
    )
    and exists (
      select 1
      from public.match_deliveries md
      join public.match_batting_turns mbt on mbt.id = md.batting_turn_id
      where md.id = expected_manish_delivery_id
        and md.innings_id = target_innings_id
        and md.delivery_sequence = 18
        and md.over_assignment_id = over_three_id
        and md.legal_ball_number = 6
        and md.striker_season_roster_id = manish_roster_id
        and md.bowler_season_roster_id = arihant_roster_id
        and md.delivery_type = 'legal'
        and md.batter_runs = 1
        and md.extra_runs = 0
        and not md.is_wicket
        and mbt.id = expected_manish_turn_id
        and mbt.batter_season_roster_id = manish_roster_id
        and mbt.turn_number = 5
        and mbt.status = 'active'
    )
    and not exists (
      select 1
      from public.match_deliveries md
      join public.match_over_assignments moa on moa.id = md.over_assignment_id
      where md.innings_id = target_innings_id
        and moa.over_number in (1, 2)
        and md.bowler_season_roster_id <> moa.bowler_season_roster_id
    ) then
    return;
  end if;

  if target_match_status <> 'live' or target_innings_status <> 'live' then
    raise exception 'the correction requires the match and first innings to remain live';
  end if;

  if exists (
    select 1
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    where ml.match_id = target_match_id
  ) then
    raise exception 'the correction must run before player stats are finalized';
  end if;

  if over_one_bowler_id <> sumit_roster_id or over_two_bowler_id <> naveen_roster_id then
    raise exception 'unexpected existing bowlers for overs 1 and 2';
  end if;

  if (select count(*) from public.match_deliveries where over_assignment_id = over_one_id) <> 6
    or (select count(*) from public.match_deliveries where over_assignment_id = over_one_id and delivery_type = 'legal') <> 6
    or (select count(*) from public.match_deliveries where over_assignment_id = over_two_id) <> 6
    or (select count(*) from public.match_deliveries where over_assignment_id = over_two_id and delivery_type = 'legal') <> 6 then
    raise exception 'overs 1 and 2 must each contain exactly six legal deliveries';
  end if;

  if exists (
    select 1
    from public.match_deliveries
    where over_assignment_id in (over_one_id, over_two_id)
      and dismissal_type = 'stumped'
  ) then
    raise exception 'manual review is required before changing a stumping over bowler';
  end if;

  if (select count(*) from public.match_deliveries where innings_id = target_innings_id) <> 17
    or (select max(delivery_sequence) from public.match_deliveries where innings_id = target_innings_id) <> 17
    or (select count(*) from public.match_deliveries where innings_id = target_innings_id and delivery_type = 'legal') <> 17
    or (select coalesce(sum(batter_runs + extra_runs), 0) from public.match_deliveries where innings_id = target_innings_id) <> 12
    or (select count(*) from public.match_deliveries where innings_id = target_innings_id and is_wicket) <> 1 then
    raise exception 'the first innings changed after inspection; reconcile it before applying this correction';
  end if;

  if exists (
    select 1
    from public.match_batting_turns
    where innings_id = target_innings_id
      and batter_season_roster_id = paras_roster_id
  ) then
    raise exception 'Paras already has a batting turn in an unexpected state';
  end if;

  select mbt.started_at
  into manish_turn_started_at
  from public.match_batting_turns mbt
  where mbt.id = expected_manish_turn_id
    and mbt.innings_id = target_innings_id
    and mbt.turn_number = 4
    and mbt.batter_season_roster_id = manish_roster_id
    and mbt.phase = 'initial'
    and mbt.status = 'active'
    and mbt.end_reason is null;

  select mbt.ended_at
  into paras_turn_started_at
  from public.match_batting_turns mbt
  where mbt.innings_id = target_innings_id
    and mbt.turn_number = 3
    and mbt.status = 'ended';

  select md.created_at, md.recorded_by
  into manish_delivery_created_at, manish_delivery_recorded_by
  from public.match_deliveries md
  where md.id = expected_manish_delivery_id
    and md.innings_id = target_innings_id
    and md.over_assignment_id = over_three_id
    and md.delivery_sequence = 17
    and md.legal_ball_number = 5
    and md.striker_season_roster_id = manish_roster_id
    and md.bowler_season_roster_id = arihant_roster_id
    and md.delivery_type = 'legal'
    and md.batter_runs = 1
    and md.extra_runs = 0
    and not md.is_wicket
    and md.batting_turn_id = expected_manish_turn_id;

  if manish_turn_started_at is null
    or paras_turn_started_at is null
    or manish_delivery_created_at is null then
    raise exception 'expected Paras-to-Manish batting transition prerequisites were not found';
  end if;

  update public.match_over_assignments moa
  set bowler_season_roster_id = case moa.over_number
        when 1 then naveen_roster_id
        when 2 then sumit_roster_id
      end,
      updated_at = now()
  where moa.innings_id = target_innings_id
    and moa.over_number in (1, 2);

  update public.match_deliveries md
  set bowler_season_roster_id = case moa.over_number
        when 1 then naveen_roster_id
        when 2 then sumit_roster_id
      end,
      updated_at = now()
  from public.match_over_assignments moa
  where moa.id = md.over_assignment_id
    and md.innings_id = target_innings_id
    and moa.over_number in (1, 2);

  update public.match_batting_turns
  set turn_number = 5,
      updated_at = now()
  where id = expected_manish_turn_id;

  insert into public.match_batting_turns (
    id,
    innings_id,
    turn_number,
    batter_season_roster_id,
    phase,
    status,
    end_reason,
    started_at,
    ended_at,
    created_at,
    updated_at
  )
  values (
    paras_turn_id,
    target_innings_id,
    4,
    paras_roster_id,
    'initial',
    'ended',
    'dismissed',
    paras_turn_started_at,
    manish_turn_started_at,
    paras_turn_started_at,
    manish_turn_started_at
  );

  update public.match_deliveries
  set delivery_sequence = 18,
      legal_ball_number = 6,
      updated_at = now()
  where id = expected_manish_delivery_id;

  insert into public.match_deliveries (
    id,
    innings_id,
    over_assignment_id,
    delivery_sequence,
    legal_ball_number,
    striker_season_roster_id,
    non_striker_season_roster_id,
    bowler_season_roster_id,
    delivery_type,
    batter_runs,
    extra_runs,
    is_wicket,
    dismissed_season_roster_id,
    dismissal_type,
    fielder_season_roster_id,
    recorded_by,
    created_at,
    updated_at,
    batting_turn_id
  )
  values (
    gen_random_uuid(),
    target_innings_id,
    over_three_id,
    17,
    5,
    paras_roster_id,
    null,
    arihant_roster_id,
    'legal',
    0,
    0,
    true,
    paras_roster_id,
    'bowled',
    null,
    manish_delivery_recorded_by,
    manish_turn_started_at,
    manish_turn_started_at,
    paras_turn_id
  );
end;
$correction$;

alter table public.match_deliveries
  enable trigger match_deliveries_prevent_confirmed_over_change;
alter table public.match_deliveries
  enable trigger match_deliveries_validate;
alter table public.match_over_assignments
  enable trigger match_over_assignments_validate_lock;
alter table public.match_over_assignments
  enable trigger match_over_assignments_validate;

do $verification$
declare
  target_match_id constant uuid := 'bd9f5c7d-69e3-4978-beab-cc5e49973ce9';
  target_innings_id constant uuid := '6d77134a-e086-4d81-b247-18101f98bdbc';
begin
  if exists (
    select 1
    from public.match_over_assignments moa
    join public.season_rosters sr on sr.id = moa.bowler_season_roster_id
    join public.players p on p.id = sr.player_id
    where moa.innings_id = target_innings_id
      and (
        (moa.over_number = 1 and p.display_name <> 'Naveen Amin')
        or (moa.over_number = 2 and p.display_name <> 'Sumit Lole')
      )
  ) then
    raise exception 'opening over bowler verification failed';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    where md.innings_id = target_innings_id
      and moa.over_number in (1, 2)
      and md.bowler_season_roster_id <> moa.bowler_season_roster_id
  ) then
    raise exception 'opening over delivery bowler verification failed';
  end if;

  if not exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    join public.season_rosters striker_sr on striker_sr.id = md.striker_season_roster_id
    join public.players striker on striker.id = striker_sr.player_id
    join public.season_rosters bowler_sr on bowler_sr.id = md.bowler_season_roster_id
    join public.players bowler on bowler.id = bowler_sr.player_id
    join public.match_batting_turns mbt on mbt.id = md.batting_turn_id
    where md.innings_id = target_innings_id
      and md.delivery_sequence = 17
      and moa.over_number = 3
      and md.legal_ball_number = 5
      and striker.display_name = 'Paras Adhiya'
      and bowler.display_name = 'Arihant Jain'
      and md.batter_runs = 0
      and md.extra_runs = 0
      and md.is_wicket
      and md.dismissal_type = 'bowled'
      and mbt.turn_number = 4
      and mbt.status = 'ended'
      and mbt.end_reason = 'dismissed'
  ) then
    raise exception 'Paras 2.5 dismissal verification failed';
  end if;

  if not exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    join public.season_rosters striker_sr on striker_sr.id = md.striker_season_roster_id
    join public.players striker on striker.id = striker_sr.player_id
    join public.season_rosters bowler_sr on bowler_sr.id = md.bowler_season_roster_id
    join public.players bowler on bowler.id = bowler_sr.player_id
    join public.match_batting_turns mbt on mbt.id = md.batting_turn_id
    where md.id = '15f3c97b-8628-422e-99cc-bcbf22af0e23'::uuid
      and md.innings_id = target_innings_id
      and md.delivery_sequence = 18
      and moa.over_number = 3
      and md.legal_ball_number = 6
      and striker.display_name = 'Manish Doijode'
      and bowler.display_name = 'Arihant Jain'
      and md.batter_runs = 1
      and md.extra_runs = 0
      and not md.is_wicket
      and mbt.turn_number = 5
      and mbt.status = 'active'
  ) then
    raise exception 'Manish 2.6 run verification failed';
  end if;

  if (select count(*) from public.match_deliveries where innings_id = target_innings_id) <> 18
    or (select max(delivery_sequence) from public.match_deliveries where innings_id = target_innings_id) <> 18
    or (select count(*) from public.match_deliveries where innings_id = target_innings_id and delivery_type = 'legal') <> 18
    or (select coalesce(sum(batter_runs + extra_runs), 0) from public.match_deliveries where innings_id = target_innings_id) <> 12
    or (select count(*) from public.match_deliveries where innings_id = target_innings_id and is_wicket) <> 2 then
    raise exception 'first-innings score invariant verification failed';
  end if;

  if exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and (
        (c.relname = 'match_over_assignments' and t.tgname in (
          'match_over_assignments_validate',
          'match_over_assignments_validate_lock'
        ))
        or (c.relname = 'match_deliveries' and t.tgname in (
          'match_deliveries_validate',
          'match_deliveries_prevent_confirmed_over_change'
        ))
      )
      and t.tgenabled <> 'O'
  ) then
    raise exception 'the correction left a scoring trigger disabled';
  end if;

  if not exists (
    select 1
    from public.matches m
    join public.match_innings mi on mi.match_id = m.id
    where m.id = target_match_id
      and m.status = 'live'
      and m.result_type is null
      and mi.id = target_innings_id
      and mi.status = 'live'
  ) then
    raise exception 'the correction unexpectedly changed match or innings status';
  end if;
end;
$verification$;
