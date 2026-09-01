-- Correct only the final delivery of the specified completed match.
do $$
declare
  target_delivery_id uuid;
  target_yug_lineup_id uuid;
begin
  select md.id
  into target_delivery_id
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  join public.match_innings mi on mi.id = md.innings_id
  where mi.match_id = '241f5f62-e726-47c5-9433-86e940c6d4f7'
    and mi.innings_number = 2
    and moa.over_number = 6
    and md.delivery_sequence = 37
    and md.legal_ball_number = 6
    and md.is_wicket
    and md.dismissal_type = 'hit_out_of_field'
    and md.striker_season_roster_id = 'a65a161e-ed69-48e5-bd1a-3703f992172f'
    and md.bowler_season_roster_id = '669d600e-0168-4147-81c4-1b16a5b9a2b1';

  if target_delivery_id is null then
    raise exception 'target final delivery is not in the expected state';
  end if;

  select ml.id
  into target_yug_lineup_id
  from public.match_lineups ml
  where ml.match_id = '241f5f62-e726-47c5-9433-86e940c6d4f7'
    and ml.season_roster_id = '90b781bd-7151-487f-b009-c4f77c8dc31b';

  if target_yug_lineup_id is null then
    raise exception 'Yug is not in the target match lineup';
  end if;

  alter table public.match_deliveries disable trigger match_deliveries_prevent_confirmed_over_change;

  update public.match_batting_turns
  set status = 'active', end_reason = null, ended_at = null, updated_at = now()
  where id = 'f4408fdc-e7c3-450b-a524-e79c32ef7f04';

  update public.match_deliveries
  set dismissal_type = 'caught',
      fielder_season_roster_id = '90b781bd-7151-487f-b009-c4f77c8dc31b',
      updated_at = now()
  where id = target_delivery_id;

  perform public.refresh_match_batting_turn('f4408fdc-e7c3-450b-a524-e79c32ef7f04');

  alter table public.match_deliveries enable trigger match_deliveries_prevent_confirmed_over_change;

  update public.match_player_stats
  set catches = catches + 1,
      updated_at = now()
  where match_lineup_id = target_yug_lineup_id;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where c.relname = 'match_deliveries'
      and t.tgname = 'match_deliveries_prevent_confirmed_over_change'
      and t.tgenabled = 'O'
  ) then
    raise exception 'confirmed-over protection trigger was not restored';
  end if;
end;
$$;
