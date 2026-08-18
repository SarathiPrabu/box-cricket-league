create or replace function public.select_match_batter(
  target_innings_id uuid,
  target_batter_season_roster_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  active_turn public.match_batting_turns%rowtype;
  batting_phase text;
  turn_id_value uuid;
  next_turn_number integer;
  historical_batting_exception boolean;
  lineup_player_count integer;
  initial_turn_count integer;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = target_innings_id
  for update;

  if innings_record.id is null or innings_record.status <> 'live' then
    raise exception 'innings is not live';
  end if;

  if (select m.status from public.matches m where m.id = innings_record.match_id) <> 'live' then
    raise exception 'match is not live';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = target_batter_season_roster_id
  ) then
    raise exception 'batsman must belong to the batting lineup';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    where md.innings_id = target_innings_id
      and md.dismissed_season_roster_id = target_batter_season_roster_id
  ) then
    raise exception 'a dismissed batsman cannot return';
  end if;

  select mbt.* into active_turn
  from public.match_batting_turns mbt
  where mbt.innings_id = target_innings_id
    and mbt.status = 'active'
  for update;

  if active_turn.id is not null then
    if active_turn.batter_season_roster_id = target_batter_season_roster_id then
      return active_turn.id;
    end if;

    if not exists (
      select 1 from public.match_deliveries md where md.batting_turn_id = active_turn.id
    ) then
      delete from public.match_batting_turns where id = active_turn.id;
    elsif active_turn.phase = 'initial' then
      raise exception 'the current batsman must complete six legal balls or be dismissed';
    else
      update public.match_batting_turns
      set status = 'ended',
          end_reason = 'switched',
          ended_at = now(),
          updated_at = now()
      where id = active_turn.id;
    end if;
  end if;

  select coalesce(m.historical_batting_exception, false)
  into historical_batting_exception
  from public.matches m
  where m.id = innings_record.match_id;

  select count(*)::integer
  into lineup_player_count
  from public.match_lineups ml
  where ml.match_id = innings_record.match_id
    and ml.season_team_id = innings_record.batting_season_team_id;

  select count(distinct mbt.batter_season_roster_id)::integer
  into initial_turn_count
  from public.match_batting_turns mbt
  where mbt.innings_id = target_innings_id
    and mbt.phase = 'initial'
    and mbt.status = 'ended'
    and mbt.end_reason in ('six_balls', 'dismissed');

  if initial_turn_count >= greatest(lineup_player_count - case when historical_batting_exception then 1 else 0 end, 0) then
    batting_phase := 'flexible';
  else
    batting_phase := 'initial';
  end if;

  if batting_phase = 'initial' and exists (
    select 1
    from public.match_batting_turns mbt
    where mbt.innings_id = target_innings_id
      and mbt.batter_season_roster_id = target_batter_season_roster_id
      and mbt.phase = 'initial'
  ) then
    raise exception 'choose a batsman who has not received an initial turn';
  end if;

  select coalesce(max(mbt.turn_number), 0) + 1
  into next_turn_number
  from public.match_batting_turns mbt
  where mbt.innings_id = target_innings_id;

  insert into public.match_batting_turns (
    innings_id,
    turn_number,
    batter_season_roster_id,
    phase
  ) values (
    target_innings_id,
    next_turn_number,
    target_batter_season_roster_id,
    batting_phase
  )
  returning id into turn_id_value;

  return turn_id_value;
end;
$$;

grant execute on function public.select_match_batter(uuid, uuid) to anon, authenticated;
