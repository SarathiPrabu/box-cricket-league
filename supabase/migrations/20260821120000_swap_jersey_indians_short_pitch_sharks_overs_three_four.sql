-- Swap the recorded bowlers for overs 3 and 4 in the live Jersey Indians vs
-- Short Pitch Sharks match without changing any delivery result or score.
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
  target_match_id constant uuid := 'f3c73fd3-ac90-4d50-9a50-68a0ab520351';
  target_innings_id uuid;
  match_status text;
  mandar_roster_id uuid := '2039ef96-f8de-4bec-8e71-13b1fcbb0c87';
  manan_roster_id uuid := 'd0cb1c43-e575-4d7c-9e7c-b4186bfa7d3e';
  over_three_id uuid;
  over_four_id uuid;
  over_three_bowler_id uuid;
  over_four_bowler_id uuid;
begin
  select m.status, mi.id
    into match_status, target_innings_id
  from public.matches m
  join public.match_innings mi on mi.match_id = m.id and mi.innings_number = 1
  where m.id = target_match_id;

  if target_innings_id is null then
    raise exception 'target Jersey Indians vs Short Pitch Sharks first innings not found';
  end if;

  select id, bowler_season_roster_id into over_three_id, over_three_bowler_id
  from public.match_over_assignments
  where innings_id = target_innings_id and over_number = 3;
  select id, bowler_season_roster_id into over_four_id, over_four_bowler_id
  from public.match_over_assignments
  where innings_id = target_innings_id and over_number = 4;

  if over_three_id is null or over_four_id is null then
    raise exception 'first-innings overs 3 and 4 must both exist';
  end if;

  if over_three_bowler_id = manan_roster_id and over_four_bowler_id = mandar_roster_id then
    return;
  end if;

  if match_status <> 'live' then
    raise exception 'the bowler correction requires the match to remain live';
  end if;

  if over_three_bowler_id <> mandar_roster_id or over_four_bowler_id <> manan_roster_id then
    raise exception 'unexpected existing bowlers for overs 3 and 4';
  end if;

  if exists (
    select 1
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    where ml.match_id = target_match_id
  ) then
    raise exception 'the bowler correction must run before player stats are finalized';
  end if;

  if (select count(*) filter (where delivery_type = 'legal') from public.match_deliveries where over_assignment_id = over_three_id) <> 6
    or (select count(*) filter (where delivery_type = 'legal') from public.match_deliveries where over_assignment_id = over_four_id) <> 6 then
    raise exception 'overs 3 and 4 must each contain six legal balls';
  end if;

  if exists (
    select 1 from public.match_deliveries
    where over_assignment_id in (over_three_id, over_four_id)
      and dismissal_type = 'stumped'
  ) then
    raise exception 'manual review is required before changing a stumping over bowler';
  end if;

  update public.match_over_assignments
  set bowler_season_roster_id = case over_number when 3 then manan_roster_id when 4 then mandar_roster_id end,
      updated_at = now()
  where id in (over_three_id, over_four_id);

  update public.match_deliveries md
  set bowler_season_roster_id = case moa.over_number when 3 then manan_roster_id when 4 then mandar_roster_id end,
      updated_at = now()
  from public.match_over_assignments moa
  where md.over_assignment_id = moa.id
    and moa.id in (over_three_id, over_four_id);
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
  target_match_id constant uuid := 'f3c73fd3-ac90-4d50-9a50-68a0ab520351';
begin
  if exists (
    select 1
    from public.match_innings mi
    join public.match_over_assignments moa on moa.innings_id = mi.id
    join public.season_rosters sr on sr.id = moa.bowler_season_roster_id
    join public.players p on p.id = sr.player_id
    where mi.match_id = target_match_id and mi.innings_number = 1
      and ((moa.over_number = 3 and p.display_name <> 'Manan Meghani')
        or (moa.over_number = 4 and p.display_name <> 'Mandar Patki'))
  ) then raise exception 'over assignment bowler verification failed'; end if;

  if exists (
    select 1
    from public.match_innings mi
    join public.match_over_assignments moa on moa.innings_id = mi.id
    join public.match_deliveries md on md.over_assignment_id = moa.id
    where mi.match_id = target_match_id and mi.innings_number = 1
      and moa.over_number in (3, 4)
      and md.bowler_season_roster_id <> moa.bowler_season_roster_id
  ) then raise exception 'delivery bowler verification failed'; end if;

  if exists (
    select 1
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and ((c.relname = 'match_over_assignments' and t.tgname in ('match_over_assignments_validate', 'match_over_assignments_validate_lock'))
        or (c.relname = 'match_deliveries' and t.tgname in ('match_deliveries_validate', 'match_deliveries_prevent_confirmed_over_change')))
      and not t.tgenabled = 'O'
  ) then raise exception 'a scoring trigger was not re-enabled'; end if;
end;
$verification$;
