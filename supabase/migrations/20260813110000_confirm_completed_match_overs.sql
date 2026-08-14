alter table public.match_over_assignments
  add column if not exists confirmed_at timestamptz;

-- Existing later-over data proves the preceding over was already accepted.
update public.match_over_assignments current_assignment
set confirmed_at = coalesce(current_assignment.confirmed_at, now())
where current_assignment.confirmed_at is null
  and (
    exists (
      select 1
      from public.match_over_assignments later_assignment
      where later_assignment.innings_id = current_assignment.innings_id
        and later_assignment.over_number > current_assignment.over_number
    )
    or exists (
      select 1
      from public.match_innings completed_innings
      where completed_innings.id = current_assignment.innings_id
        and completed_innings.status = 'completed'
    )
  );

create unique index match_over_assignments_one_open_over
  on public.match_over_assignments (innings_id)
  where confirmed_at is null;

create or replace function public.validate_match_over_lock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  legal_ball_count integer;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = new.innings_id;

  if new.over_number > 1 and not exists (
    select 1
    from public.match_over_assignments previous_assignment
    where previous_assignment.innings_id = new.innings_id
      and previous_assignment.over_number = new.over_number - 1
      and previous_assignment.confirmed_at is not null
  ) then
    raise exception 'confirm the completed over before setting the next over';
  end if;

  if tg_op = 'UPDATE' and old.confirmed_at is not null then
    if new.confirmed_at is null
      or new.over_number is distinct from old.over_number
      or new.batting_slot_season_roster_id is distinct from old.batting_slot_season_roster_id
      or new.bowler_season_roster_id is distinct from old.bowler_season_roster_id
      or new.wicketkeeper_season_roster_id is distinct from old.wicketkeeper_season_roster_id then
      raise exception 'a confirmed over is locked';
    end if;
  end if;

  if tg_op = 'UPDATE'
    and old.confirmed_at is null
    and new.confirmed_at is not null
    and innings_record.status = 'live' then
    select count(*) filter (where md.delivery_type = 'legal')::integer
    into legal_ball_count
    from public.match_deliveries md
    where md.over_assignment_id = new.id;

    if legal_ball_count <> innings_record.balls_per_over then
      raise exception 'only an over with six legal balls can be confirmed';
    end if;

    if exists (
      select 1
      from public.match_over_assignments later_assignment
      where later_assignment.innings_id = new.innings_id
        and later_assignment.over_number > new.over_number
    ) then
      raise exception 'only the current over can be confirmed';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists match_over_assignments_validate_lock
on public.match_over_assignments;

create trigger match_over_assignments_validate_lock
before insert or update on public.match_over_assignments
for each row execute function public.validate_match_over_lock();

create or replace function public.prevent_confirmed_over_delivery_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_over_assignment_id uuid;
begin
  target_over_assignment_id := case when tg_op = 'DELETE' then old.over_assignment_id else new.over_assignment_id end;

  if exists (
    select 1
    from public.match_over_assignments moa
    where moa.id = target_over_assignment_id
      and moa.confirmed_at is not null
  ) then
    raise exception 'a confirmed over is locked';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists match_deliveries_prevent_confirmed_over_change
on public.match_deliveries;

create trigger match_deliveries_prevent_confirmed_over_change
before insert or update or delete on public.match_deliveries
for each row execute function public.prevent_confirmed_over_delivery_change();

create or replace function public.validate_innings_over_confirmation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'live' and new.status = 'completed' and exists (
    select 1
    from public.match_over_assignments moa
    where moa.innings_id = new.id
      and moa.confirmed_at is null
      and (
        select count(*)
        from public.match_deliveries md
        where md.over_assignment_id = moa.id
          and md.delivery_type = 'legal'
      ) = new.balls_per_over
  ) then
    raise exception 'confirm the completed over before ending the innings';
  end if;

  return new;
end;
$$;

drop trigger if exists match_innings_validate_over_confirmation
on public.match_innings;

create trigger match_innings_validate_over_confirmation
before update of status on public.match_innings
for each row execute function public.validate_innings_over_confirmation();

create or replace function public.lock_ended_innings_overs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'live' and new.status = 'completed' then
    update public.match_over_assignments
    set confirmed_at = coalesce(confirmed_at, now()),
        updated_at = now()
    where innings_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists match_innings_lock_ended_overs
on public.match_innings;

create trigger match_innings_lock_ended_overs
after update of status on public.match_innings
for each row execute function public.lock_ended_innings_overs();

create or replace function public.confirm_match_over(target_over_assignment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
  legal_ball_count integer;
begin
  select moa.* into assignment_record
  from public.match_over_assignments moa
  where moa.id = target_over_assignment_id
  for update;

  if assignment_record.id is null then
    raise exception 'over assignment not found';
  end if;

  if assignment_record.confirmed_at is not null then
    return assignment_record.id;
  end if;

  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = assignment_record.innings_id
  for update;

  if innings_record.status <> 'live' then
    raise exception 'only a live innings over can be confirmed';
  end if;

  if exists (
    select 1
    from public.match_over_assignments later_assignment
    where later_assignment.innings_id = assignment_record.innings_id
      and later_assignment.over_number > assignment_record.over_number
  ) then
    raise exception 'only the current over can be confirmed';
  end if;

  select count(*) filter (where md.delivery_type = 'legal')::integer
  into legal_ball_count
  from public.match_deliveries md
  where md.over_assignment_id = target_over_assignment_id;

  if legal_ball_count <> innings_record.balls_per_over then
    raise exception 'only an over with six legal balls can be confirmed';
  end if;

  update public.match_over_assignments
  set confirmed_at = now(),
      updated_at = now()
  where id = target_over_assignment_id;

  return target_over_assignment_id;
end;
$$;

grant execute on function public.confirm_match_over(uuid) to anon, authenticated;

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
