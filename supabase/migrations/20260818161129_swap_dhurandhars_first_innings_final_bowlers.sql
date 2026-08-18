-- Correct the recorded bowling order in the live Short Pitch Sharks vs
-- Dhurandhars United match without changing any delivery result or score.
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
  target_match_id constant uuid := '64ccac7d-0228-47b9-9c5c-398f85ac991e';
  target_innings_id uuid;
  match_status text;
  adarsh_roster_id uuid;
  amar_roster_id uuid;
  over_five_id uuid;
  over_six_id uuid;
  over_five_bowler_id uuid;
  over_six_bowler_id uuid;
  over_five_legal_balls integer;
  over_six_legal_balls integer;
begin
  select m.status, mi.id
  into match_status, target_innings_id
  from public.matches m
  join public.match_innings mi
    on mi.match_id = m.id
   and mi.innings_number = 1
  join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
  join public.teams home_team on home_team.id = home_season_team.team_id
  join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
  join public.teams away_team on away_team.id = away_season_team.team_id
  where m.id = target_match_id
    and home_team.name = 'Short Pitch Sharks'
    and away_team.name = 'Dhurandhars United';

  if target_innings_id is null then
    raise exception 'target Short Pitch Sharks vs Dhurandhars United first innings not found';
  end if;

  select ml.season_roster_id
  into adarsh_roster_id
  from public.match_lineups ml
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  join public.match_innings mi on mi.match_id = ml.match_id
  where ml.match_id = target_match_id
    and mi.id = target_innings_id
    and ml.season_team_id = mi.bowling_season_team_id
    and p.display_name = 'Adarsh Chhajed';

  select ml.season_roster_id
  into amar_roster_id
  from public.match_lineups ml
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  join public.match_innings mi on mi.match_id = ml.match_id
  where ml.match_id = target_match_id
    and mi.id = target_innings_id
    and ml.season_team_id = mi.bowling_season_team_id
    and p.display_name = 'Amar Hete';

  if adarsh_roster_id is null or amar_roster_id is null then
    raise exception 'Adarsh and Amar must both be in the first-innings bowling lineup';
  end if;

  select moa.id, moa.bowler_season_roster_id
  into over_five_id, over_five_bowler_id
  from public.match_over_assignments moa
  where moa.innings_id = target_innings_id
    and moa.over_number = 5;

  select moa.id, moa.bowler_season_roster_id
  into over_six_id, over_six_bowler_id
  from public.match_over_assignments moa
  where moa.innings_id = target_innings_id
    and moa.over_number = 6;

  if over_five_id is null or over_six_id is null then
    raise exception 'first-innings overs 5 and 6 must both exist';
  end if;

  if over_five_bowler_id = amar_roster_id and over_six_bowler_id = adarsh_roster_id
    and not exists (
      select 1
      from public.match_deliveries md
      join public.match_over_assignments moa on moa.id = md.over_assignment_id
      where md.innings_id = target_innings_id
        and (
          (moa.over_number = 5 and md.bowler_season_roster_id <> amar_roster_id)
          or (moa.over_number = 6 and md.bowler_season_roster_id <> adarsh_roster_id)
        )
    ) then
    return;
  end if;

  if match_status <> 'live' then
    raise exception 'the bowler correction requires the match to remain live';
  end if;

  if exists (
    select 1
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    where ml.match_id = target_match_id
  ) then
    raise exception 'the bowler correction must run before player stats are finalized';
  end if;

  if over_five_bowler_id <> adarsh_roster_id or over_six_bowler_id <> amar_roster_id then
    raise exception 'unexpected existing bowlers for overs 5 and 6';
  end if;

  select count(*) filter (where md.delivery_type = 'legal')::integer
  into over_five_legal_balls
  from public.match_deliveries md
  where md.over_assignment_id = over_five_id
    and md.bowler_season_roster_id = adarsh_roster_id;

  select count(*) filter (where md.delivery_type = 'legal')::integer
  into over_six_legal_balls
  from public.match_deliveries md
  where md.over_assignment_id = over_six_id
    and md.bowler_season_roster_id = amar_roster_id;

  if over_five_legal_balls <> 6 or over_six_legal_balls <> 6 then
    raise exception 'overs 5 and 6 must each contain six legal balls from the recorded bowler';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    where md.over_assignment_id in (over_five_id, over_six_id)
      and md.dismissal_type = 'stumped'
  ) then
    raise exception 'manual review is required before changing a stumping over bowler';
  end if;

  update public.match_over_assignments moa
  set bowler_season_roster_id = case moa.over_number
        when 5 then amar_roster_id
        when 6 then adarsh_roster_id
      end,
      updated_at = now()
  where moa.innings_id = target_innings_id
    and moa.over_number in (5, 6);

  update public.match_deliveries md
  set bowler_season_roster_id = case moa.over_number
        when 5 then amar_roster_id
        when 6 then adarsh_roster_id
      end,
      updated_at = now()
  from public.match_over_assignments moa
  where moa.id = md.over_assignment_id
    and md.innings_id = target_innings_id
    and moa.over_number in (5, 6);
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
  target_match_id constant uuid := '64ccac7d-0228-47b9-9c5c-398f85ac991e';
begin
  if exists (
    select 1
    from public.match_innings mi
    join public.match_over_assignments moa on moa.innings_id = mi.id
    join public.season_rosters sr on sr.id = moa.bowler_season_roster_id
    join public.players p on p.id = sr.player_id
    where mi.match_id = target_match_id
      and mi.innings_number = 1
      and (
        (moa.over_number = 5 and p.display_name <> 'Amar Hete')
        or (moa.over_number = 6 and p.display_name <> 'Adarsh Chhajed')
      )
  ) then
    raise exception 'over assignment bowler verification failed';
  end if;

  if exists (
    select 1
    from public.match_innings mi
    join public.match_over_assignments moa on moa.innings_id = mi.id
    join public.match_deliveries md on md.over_assignment_id = moa.id
    where mi.match_id = target_match_id
      and mi.innings_number = 1
      and moa.over_number in (5, 6)
      and md.bowler_season_roster_id <> moa.bowler_season_roster_id
  ) then
    raise exception 'delivery bowler verification failed';
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
    raise exception 'bowler correction left a scoring trigger disabled';
  end if;
end;
$verification$;
