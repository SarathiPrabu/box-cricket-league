alter table public.matches
  add column if not exists historical_batting_exception boolean not null default false;

comment on column public.matches.historical_batting_exception is
  'Allows a historical innings to complete without a batting slot for every lineup player.';

create or replace function public.set_match_historical_batting_exception(
  target_match_id uuid,
  enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  match_status text;
begin
  select m.status
  into match_status
  from public.matches m
  where m.id = target_match_id
  for update;

  if match_status is null then
    raise exception 'match not found';
  end if;

  if match_status <> 'scheduled' then
    raise exception 'historical batting exception must be set before the match starts';
  end if;

  update public.matches
  set historical_batting_exception = enabled,
      updated_at = now()
  where id = target_match_id;

  return enabled;
end;
$$;

grant execute on function public.set_match_historical_batting_exception(uuid, boolean) to anon, authenticated;

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

  if historical_batting_exception and initial_turn_count >= greatest(lineup_player_count - 1, 0) then
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
      ) then
      raise exception 'a full innings requires one batting slot for every player';
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

create or replace function public.get_match_scoring_state(target_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  state jsonb;
begin
  select jsonb_build_object(
    'match', (
      select jsonb_build_object(
        'id', m.id,
        'season_id', m.season_id,
        'status', m.status,
        'result_type', m.result_type,
        'winner_season_team_id', m.winner_season_team_id,
        'home_season_team_id', m.home_season_team_id,
        'away_season_team_id', m.away_season_team_id,
        'home_team_name', home_team.name,
        'away_team_name', away_team.name,
        'match_date', m.match_date,
        'venue', m.venue,
        'historical_batting_exception', m.historical_batting_exception,
        'balls_per_over', s.balls_per_over,
        'max_overs_per_player', s.max_overs_per_player
      )
      from public.matches m
      join public.seasons s on s.id = m.season_id
      join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
      join public.teams home_team on home_team.id = home_season_team.team_id
      join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
      join public.teams away_team on away_team.id = away_season_team.team_id
      where m.id = target_match_id
    ),
    'lineups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ml.id,
        'season_team_id', ml.season_team_id,
        'season_roster_id', ml.season_roster_id,
        'player_id', sr.player_id,
        'player_name', p.display_name,
        'is_captain', ml.is_captain
      ) order by ml.season_team_id, p.display_name)
      from public.match_lineups ml
      join public.season_rosters sr on sr.id = ml.season_roster_id
      join public.players p on p.id = sr.player_id
      where ml.match_id = target_match_id
    ), '[]'::jsonb),
    'innings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mi.id,
        'innings_number', mi.innings_number,
        'batting_season_team_id', mi.batting_season_team_id,
        'bowling_season_team_id', mi.bowling_season_team_id,
        'overs_limit', mi.overs_limit,
        'balls_per_over', mi.balls_per_over,
        'legal_balls_limit', mi.legal_balls_limit,
        'max_overs_per_player', mi.max_overs_per_player,
        'target_score', mi.target_score,
        'status', mi.status,
        'batting_turns', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', mbt.id,
            'turn_number', mbt.turn_number,
            'batter_season_roster_id', mbt.batter_season_roster_id,
            'batter_name', batter.display_name,
            'phase', mbt.phase,
            'status', mbt.status,
            'end_reason', mbt.end_reason,
            'legal_balls_faced', (
              select count(*)
              from public.match_deliveries turn_delivery
              where turn_delivery.batting_turn_id = mbt.id
                and turn_delivery.delivery_type = 'legal'
            )
          ) order by mbt.turn_number)
          from public.match_batting_turns mbt
          join public.season_rosters batter_roster on batter_roster.id = mbt.batter_season_roster_id
          join public.players batter on batter.id = batter_roster.player_id
          where mbt.innings_id = mi.id
        ), '[]'::jsonb),
        'overs', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', moa.id,
            'over_number', moa.over_number,
            'confirmed_at', moa.confirmed_at,
            'batting_slot_season_roster_id', moa.batting_slot_season_roster_id,
            'bowler_season_roster_id', moa.bowler_season_roster_id,
            'wicketkeeper_season_roster_id', moa.wicketkeeper_season_roster_id,
            'batting_slot_name', batting_player.display_name,
            'bowler_name', bowler_player.display_name,
            'wicketkeeper_name', keeper_player.display_name,
            'deliveries', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', md.id,
                'batting_turn_id', md.batting_turn_id,
                'delivery_sequence', md.delivery_sequence,
                'legal_ball_number', md.legal_ball_number,
                'striker_season_roster_id', md.striker_season_roster_id,
                'non_striker_season_roster_id', md.non_striker_season_roster_id,
                'bowler_season_roster_id', md.bowler_season_roster_id,
                'delivery_type', md.delivery_type,
                'batter_runs', md.batter_runs,
                'extra_runs', md.extra_runs,
                'is_wicket', md.is_wicket,
                'dismissed_season_roster_id', md.dismissed_season_roster_id,
                'dismissal_type', md.dismissal_type,
                'fielder_season_roster_id', md.fielder_season_roster_id
              ) order by md.delivery_sequence)
              from public.match_deliveries md
              where md.over_assignment_id = moa.id
            ), '[]'::jsonb)
          ) order by moa.over_number)
          from public.match_over_assignments moa
          left join public.season_rosters batting_roster on batting_roster.id = moa.batting_slot_season_roster_id
          left join public.players batting_player on batting_player.id = batting_roster.player_id
          join public.season_rosters bowler_roster on bowler_roster.id = moa.bowler_season_roster_id
          join public.players bowler_player on bowler_player.id = bowler_roster.player_id
          join public.season_rosters keeper_roster on keeper_roster.id = moa.wicketkeeper_season_roster_id
          join public.players keeper_player on keeper_player.id = keeper_roster.player_id
          where moa.innings_id = mi.id
        ), '[]'::jsonb)
      ) order by mi.innings_number)
      from public.match_innings mi
      where mi.match_id = target_match_id
    ), '[]'::jsonb)
  ) into state;

  return state;
end;
$$;

grant execute on function public.get_match_scoring_state(uuid) to anon, authenticated;
