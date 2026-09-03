begin;

do $repair$
declare
  target_match_id uuid := '47a182bd-384b-425e-947a-1a33b2bd8a73'::uuid;
  target_innings_id uuid := 'c78414fa-760b-46a9-b9ff-738f2907d0a2'::uuid;
  target_over_assignment_id uuid := 'ea56e6c8-687b-4bc1-adda-274635122bc6'::uuid;
  target_delivery_id uuid := 'e2fe72e9-3a50-4bba-9043-7f7f38c3fa68'::uuid;
  target_batting_turn_id uuid := 'fe8ba27b-9a74-43a9-aadd-fdaf051b78e9'::uuid;
  active_batting_turn_id uuid := '9c0a81fb-6320-4580-ab46-bc4897465329'::uuid;
  expected_amal_roster_id uuid := '48a81ea0-3e5c-49a0-9ef8-df0de6165a4e'::uuid;
  expected_bowler_roster_id uuid := 'bceac77a-aa75-48b5-ac3d-97d16bba604b'::uuid;
  target_delivery record;
  target_over record;
  inserted_delivery_id uuid;
begin
  select md.*
  into target_delivery
  from public.match_deliveries md
  where md.id = target_delivery_id
    and md.innings_id = target_innings_id;

  if not found
     or target_delivery.delivery_sequence <> 11
     or target_delivery.batting_turn_id <> target_batting_turn_id
     or target_delivery.striker_season_roster_id <> expected_amal_roster_id
     or target_delivery.bowler_season_roster_id <> expected_bowler_roster_id
     or not target_delivery.is_wicket
     or target_delivery.dismissal_type <> 'hit_out_of_field'
     or target_delivery.batter_runs <> 0
     or target_delivery.extra_runs <> 0 then
    raise exception 'unexpected target wicket state for match 47a182bd over 2 ball 3';
  end if;

  select moa.*
  into target_over
  from public.match_over_assignments moa
  where moa.id = target_over_assignment_id
    and moa.innings_id = target_innings_id;

  if not found or target_over.over_number <> 2 or target_over.confirmed_at is not null then
    raise exception 'target over is missing or already confirmed';
  end if;

  if not exists (
    select 1
    from public.matches m
    join public.match_innings mi on mi.match_id = m.id
    where m.id = target_match_id
      and m.status = 'live'
      and mi.id = target_innings_id
      and mi.status = 'live'
  ) then
    raise exception 'target match or innings is not live';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    where md.over_assignment_id = target_over_assignment_id
      and md.delivery_sequence >= 12
  ) then
    raise exception 'target over already contains a later delivery';
  end if;

  update public.match_batting_turns
  set status = 'ended',
      end_reason = 'switched',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where id = active_batting_turn_id
    and status = 'active';

  update public.match_batting_turns
  set status = 'active',
      end_reason = null,
      ended_at = null,
      updated_at = now()
  where id = target_batting_turn_id
    and batter_season_roster_id = expected_amal_roster_id
    and innings_id = target_innings_id;

  update public.match_deliveries
  set batter_runs = 1,
      is_wicket = false,
      dismissed_season_roster_id = null,
      dismissal_type = null,
      fielder_season_roster_id = null,
      updated_at = now()
  where id = target_delivery_id
    and batting_turn_id = target_batting_turn_id;

  if not found then
    raise exception 'target delivery was not converted to one run';
  end if;

  insert into public.match_deliveries (
    innings_id,
    over_assignment_id,
    batting_turn_id,
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
    fielder_season_roster_id
  ) values (
    target_innings_id,
    target_over_assignment_id,
    target_batting_turn_id,
    12,
    4,
    expected_amal_roster_id,
    null,
    expected_bowler_roster_id,
    'legal',
    0,
    0,
    true,
    expected_amal_roster_id,
    'hit_out_of_field',
    null
  )
  returning id into inserted_delivery_id;

  perform public.refresh_match_batting_turn(target_batting_turn_id);

  update public.match_batting_turns
  set status = 'active',
      end_reason = null,
      ended_at = null,
      updated_at = now()
  where id = active_batting_turn_id;
end
$repair$;

commit;

