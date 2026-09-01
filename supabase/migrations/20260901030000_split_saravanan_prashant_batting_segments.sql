do $$
declare
  target_innings_id uuid := 'e1c31a62-4479-43b2-95e3-810ef1edda72';
  saravanan_turn_id uuid := 'b0f29fdd-dbb9-429b-8b20-e6c367a3a5a3';
  empty_turn_id uuid := 'e65043fe-4908-4628-be0b-bb113f1c819f';
  prashant_roster_id uuid := '84afeb53-6ff7-476f-aae5-99a39a1dd345';
begin
  if not exists (select 1 from public.match_innings where id=target_innings_id and status='live') then
    raise exception 'target innings is not live';
  end if;

  if (select count(*) from public.match_deliveries where innings_id=target_innings_id and delivery_sequence between 30 and 35) <> 6 then
    raise exception 'expected six deliveries in sequences 30 through 35';
  end if;

  if exists (select 1 from public.match_deliveries where innings_id=target_innings_id and delivery_sequence between 30 and 35 and batting_turn_id <> saravanan_turn_id) then
    raise exception 'target deliveries are not currently in Saravanan turn 7';
  end if;

  alter table public.match_deliveries disable trigger match_deliveries_prevent_confirmed_over_change;
  alter table public.match_deliveries disable trigger match_deliveries_validate;

  delete from public.match_deliveries
  where innings_id=target_innings_id and delivery_sequence >= 36;

  delete from public.match_batting_turns
  where id=empty_turn_id
    and innings_id=target_innings_id
    and status='active'
    and not exists (select 1 from public.match_deliveries where batting_turn_id=empty_turn_id);

  update public.match_batting_turns
  set status='ended', end_reason='switched', ended_at=coalesce(ended_at, now()), updated_at=now()
  where id=saravanan_turn_id;

  insert into public.match_batting_turns (id, innings_id, turn_number, batter_season_roster_id, phase, status, end_reason, ended_at)
  values (empty_turn_id, target_innings_id, 8, prashant_roster_id, 'flexible', 'active', null, null);

  update public.match_deliveries
  set batting_turn_id=empty_turn_id,
      striker_season_roster_id=prashant_roster_id,
      is_wicket=(delivery_sequence=35),
      dismissed_season_roster_id=case when delivery_sequence=35 then prashant_roster_id else null end,
      dismissal_type=case when delivery_sequence=35 then 'hit_out_of_field' else null end,
      fielder_season_roster_id=null,
      updated_at=now()
  where innings_id=target_innings_id and delivery_sequence between 30 and 35;

  alter table public.match_deliveries enable trigger match_deliveries_validate;
  alter table public.match_deliveries enable trigger match_deliveries_prevent_confirmed_over_change;

  perform public.refresh_match_batting_turn(empty_turn_id);
end;
$$;
