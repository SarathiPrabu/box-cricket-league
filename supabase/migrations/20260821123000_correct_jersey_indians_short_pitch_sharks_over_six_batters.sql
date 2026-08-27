-- Correct only the batting segment in over 6 of the live Jersey Indians vs
-- Short Pitch Sharks match. Delivery results and ball 6 remain unchanged.
alter table public.match_deliveries
  disable trigger match_deliveries_validate;
alter table public.match_deliveries
  disable trigger match_deliveries_prevent_confirmed_over_change;

do $correction$
declare
  target_match_id constant uuid := 'f3c73fd3-ac90-4d50-9a50-68a0ab520351';
  target_innings_id uuid;
  sumit_roster_id uuid := 'c029d381-4506-4d27-a65d-73951f1b9f78';
  swapnil_roster_id uuid := '8be398ef-3a35-48c9-b390-37e61df51a4f';
  sumit_turn_id uuid;
  swapnil_turn_id uuid;
  match_status text;
  ball_four_id uuid;
  ball_five_id uuid;
begin
  select m.status, mi.id
    into match_status, target_innings_id
  from public.matches m
  join public.match_innings mi on mi.match_id = m.id and mi.innings_number = 1
  where m.id = target_match_id;

  if target_innings_id is null or match_status <> 'live' then
    raise exception 'target live Jersey Indians vs Short Pitch Sharks innings not found';
  end if;

  select md.id into ball_four_id
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = target_innings_id and moa.over_number = 6 and md.legal_ball_number = 4
    and md.striker_season_roster_id = sumit_roster_id and not md.is_wicket;

  select md.id into ball_five_id
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = target_innings_id and moa.over_number = 6 and md.legal_ball_number = 5
    and md.striker_season_roster_id = sumit_roster_id and md.is_wicket
    and md.dismissed_season_roster_id = sumit_roster_id;

  if ball_four_id is null or ball_five_id is null then
    raise exception 'expected Sumit over-6 balls 4 and 5 were not found';
  end if;

  select mbt.id into sumit_turn_id
  from public.match_batting_turns mbt
  where mbt.id = '484c856f-1ec1-4c3e-a572-fa72330ffe40'::uuid
    and mbt.innings_id = target_innings_id
    and mbt.batter_season_roster_id = sumit_roster_id
    and mbt.phase = 'flexible';

  if sumit_turn_id is null then
    raise exception 'expected Sumit flexible batting turn was not found';
  end if;

  if exists (select 1 from public.match_player_stats mps join public.match_lineups ml on ml.id = mps.match_lineup_id where ml.match_id = target_match_id) then
    raise exception 'the batting correction must run before player stats are finalized';
  end if;

  if exists (
    select 1 from public.match_deliveries md
    where md.innings_id = target_innings_id
      and md.batting_turn_id is not null
      and md.batting_turn_id <> sumit_turn_id
      and md.delivery_sequence in (36, 37)
  ) then
    raise exception 'over-6 balls 4 and 5 already belong to another batting turn';
  end if;

  select id into swapnil_turn_id
  from public.match_batting_turns
  where innings_id = target_innings_id and batter_season_roster_id = swapnil_roster_id and phase = 'flexible'
  order by turn_number desc limit 1;

  if swapnil_turn_id is null then
    insert into public.match_batting_turns (innings_id, turn_number, batter_season_roster_id, phase, status, end_reason, ended_at)
    select target_innings_id, coalesce(max(turn_number), 0) + 1, swapnil_roster_id, 'flexible', 'ended', 'dismissed', now()
    from public.match_batting_turns where innings_id = target_innings_id
    returning id into swapnil_turn_id;
  end if;

  update public.match_batting_turns
  set status = 'ended', end_reason = 'switched', ended_at = coalesce(ended_at, now()), updated_at = now()
  where id = sumit_turn_id;

  update public.match_deliveries
  set striker_season_roster_id = swapnil_roster_id, batting_turn_id = swapnil_turn_id, updated_at = now()
  where id = ball_four_id;

  update public.match_deliveries
  set striker_season_roster_id = swapnil_roster_id,
      batting_turn_id = swapnil_turn_id,
      dismissed_season_roster_id = swapnil_roster_id,
      updated_at = now()
  where id = ball_five_id;

  update public.match_batting_turns
  set status = 'ended', end_reason = 'dismissed', ended_at = now(), updated_at = now()
  where id = swapnil_turn_id;
end;
$correction$;

alter table public.match_deliveries
  enable trigger match_deliveries_prevent_confirmed_over_change;
alter table public.match_deliveries
  enable trigger match_deliveries_validate;

do $verification$
declare
  target_match_id constant uuid := 'f3c73fd3-ac90-4d50-9a50-68a0ab520351';
begin
  if exists (
    select 1 from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    join public.season_rosters sr on sr.id = md.striker_season_roster_id
    join public.players p on p.id = sr.player_id
    where md.innings_id = (select id from public.match_innings where match_id = target_match_id and innings_number = 1)
      and moa.over_number = 6
      and ((md.legal_ball_number in (1, 2, 3) and p.display_name <> 'Sumit Lole')
        or (md.legal_ball_number in (4, 5) and p.display_name <> 'Swapnil Shah')
        or (md.legal_ball_number = 6 and p.display_name <> 'Arihant Jain'))
  ) then raise exception 'over-6 striker verification failed'; end if;

  if exists (
    select 1 from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    join public.season_rosters sr on sr.id = md.dismissed_season_roster_id
    join public.players p on p.id = sr.player_id
    where md.innings_id = (select id from public.match_innings where match_id = target_match_id and innings_number = 1)
      and moa.over_number = 6 and md.legal_ball_number = 5 and p.display_name <> 'Swapnil Shah'
  ) then raise exception 'over-6 dismissal verification failed'; end if;

  if exists (
    select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'match_deliveries'
      and t.tgname in ('match_deliveries_validate', 'match_deliveries_prevent_confirmed_over_change')
      and t.tgenabled <> 'O'
  ) then raise exception 'a delivery trigger was not re-enabled'; end if;
end;
$verification$;
