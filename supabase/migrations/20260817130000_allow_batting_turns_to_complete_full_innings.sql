create or replace function public.complete_match_innings(target_innings_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  innings_score integer;
  legal_ball_count integer;
  all_out boolean;
  target_reached boolean;
  batting_lineup_count integer;
  historical_batting_exception boolean;
  next_innings_id uuid;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = target_innings_id
  for update;

  if innings_record.status <> 'live' then
    raise exception 'innings is already completed';
  end if;

  select coalesce(m.historical_batting_exception, false)
  into historical_batting_exception
  from public.matches m
  where m.id = innings_record.match_id;

  select
    count(*) filter (where md.delivery_type = 'legal')::integer,
    coalesce(sum(md.batter_runs + md.extra_runs)::integer, 0)
  into legal_ball_count, innings_score
  from public.match_deliveries md
  where md.innings_id = target_innings_id;

  select not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.batting_season_team_id
      and not exists (
        select 1
        from public.match_deliveries dismissed
        where dismissed.innings_id = target_innings_id
          and dismissed.dismissed_season_roster_id = ml.season_roster_id
      )
  ) into all_out;

  target_reached := innings_record.target_score is not null and innings_score >= innings_record.target_score;

  if legal_ball_count < innings_record.legal_balls_limit and not all_out and not target_reached then
    raise exception 'innings has not reached its ending condition';
  end if;

  if legal_ball_count = innings_record.legal_balls_limit then
    if (
      select count(*)
      from public.match_over_assignments moa
      where moa.innings_id = target_innings_id
    ) <> innings_record.overs_limit
    or exists (
      select 1
      from public.match_over_assignments moa
      where moa.innings_id = target_innings_id
      group by moa.bowler_season_roster_id
      having count(*) > innings_record.max_overs_per_player
    ) then
      raise exception 'a full innings exceeds the season over limit';
    end if;

    select count(*)::integer into batting_lineup_count
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.batting_season_team_id;

    if not historical_batting_exception
      and batting_lineup_count = innings_record.overs_limit
      and exists (
        select 1
        from public.match_lineups ml
        where ml.match_id = innings_record.match_id
          and ml.season_team_id = innings_record.batting_season_team_id
          and not exists (
            select 1
            from public.match_over_assignments moa
            where moa.innings_id = target_innings_id
              and moa.batting_slot_season_roster_id = ml.season_roster_id
          )
          and not exists (
            select 1
            from public.match_batting_turns mbt
            where mbt.innings_id = target_innings_id
              and mbt.batter_season_roster_id = ml.season_roster_id
              and mbt.phase = 'initial'
              and mbt.status = 'ended'
              and mbt.end_reason in ('six_balls', 'dismissed')
          )
      ) then
      raise exception 'a full innings requires one batting slot or completed initial turn for every player';
    end if;
  end if;

  update public.match_innings
  set status = 'completed',
      total_runs = innings_score,
      completed_at = now(),
      updated_at = now()
  where id = target_innings_id;

  if innings_record.innings_number = 1 then
    insert into public.match_innings (
      match_id,
      innings_number,
      batting_season_team_id,
      bowling_season_team_id,
      overs_limit,
      balls_per_over,
      legal_balls_limit,
      max_overs_per_player,
      target_score,
      status
    ) values (
      innings_record.match_id,
      2,
      innings_record.bowling_season_team_id,
      innings_record.batting_season_team_id,
      innings_record.overs_limit,
      innings_record.balls_per_over,
      innings_record.legal_balls_limit,
      innings_record.max_overs_per_player,
      innings_score + 1,
      'live'
    ) returning id into next_innings_id;

    return next_innings_id;
  end if;

  return null;
end;
$$;

grant execute on function public.complete_match_innings(uuid) to anon, authenticated;
