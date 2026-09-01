do $$
declare
  target_innings_id uuid := '3de72610-eff7-42e6-89d1-30bdfdece6b0';
  target_delivery_id uuid := '6ca10c75-15dd-4c9a-afed-c1f1192052d5';
  sanjay_roster_id uuid := '35491da2-852a-4931-bcb3-e98975a34483';
  target_turn_id uuid := 'dc687e13-ac7c-4655-914a-98f6a4852756';
  following_delivery_count integer;
begin
  if not exists (
    select 1 from public.match_innings
    where id = target_innings_id and status = 'live'
  ) then
    raise exception 'target innings is not live';
  end if;

  if not exists (
    select 1 from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    where md.id = target_delivery_id
      and md.innings_id = target_innings_id
      and moa.over_number = 3
      and md.delivery_sequence = 16
      and md.batting_turn_id = target_turn_id
      and md.is_wicket = false
      and md.dismissed_season_roster_id is null
      and md.dismissal_type is null
  ) then
    raise exception 'target delivery does not match the expected pre-repair state';
  end if;

  select count(*) into following_delivery_count
  from public.match_deliveries md
  where md.innings_id = target_innings_id
    and md.delivery_sequence > 16;

  if following_delivery_count <> 3 then
    raise exception 'expected exactly 3 following deliveries, found %', following_delivery_count;
  end if;

  alter table public.match_deliveries disable trigger match_deliveries_prevent_confirmed_over_change;

  update public.match_batting_turns
  set status = 'active',
      end_reason = null,
      ended_at = null,
      updated_at = now()
  where id = target_turn_id;

  update public.match_deliveries
  set striker_season_roster_id = sanjay_roster_id,
      is_wicket = true,
      dismissed_season_roster_id = sanjay_roster_id,
      dismissal_type = 'hit_out_of_field',
      updated_at = now()
  where id = target_delivery_id;

  delete from public.match_deliveries
  where innings_id = target_innings_id
    and delivery_sequence > 16;

  perform public.refresh_match_batting_turn(target_turn_id);

  alter table public.match_deliveries enable trigger match_deliveries_prevent_confirmed_over_change;
end;
$$;
