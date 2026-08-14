create table public.match_batting_turns (
  id uuid primary key default extensions.gen_random_uuid(),
  innings_id uuid not null references public.match_innings(id) on delete cascade,
  turn_number integer not null,
  batter_season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  phase text not null,
  status text not null default 'active',
  end_reason text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_batting_turns_number_check check (turn_number > 0),
  constraint match_batting_turns_phase_check check (phase in ('initial', 'flexible')),
  constraint match_batting_turns_status_check check (status in ('active', 'ended')),
  constraint match_batting_turns_end_reason_check check (
    end_reason is null or end_reason in ('six_balls', 'dismissed', 'switched', 'innings_end')
  ),
  constraint match_batting_turns_status_reason_check check (
    (status = 'active' and end_reason is null and ended_at is null)
    or (status = 'ended' and end_reason is not null and ended_at is not null)
  ),
  constraint match_batting_turns_innings_number_unique unique (innings_id, turn_number)
);

create unique index match_batting_turns_active_unique
  on public.match_batting_turns (innings_id)
  where status = 'active';

create unique index match_batting_turns_initial_batter_unique
  on public.match_batting_turns (innings_id, batter_season_roster_id)
  where phase = 'initial';

create index match_batting_turns_innings_id_idx
  on public.match_batting_turns (innings_id);

alter table public.match_deliveries
  add column if not exists batting_turn_id uuid references public.match_batting_turns(id) on delete restrict;

create index if not exists match_deliveries_batting_turn_id_idx
  on public.match_deliveries (batting_turn_id);

alter table public.match_over_assignments
  alter column batting_slot_season_roster_id drop not null;

create trigger match_batting_turns_set_updated_at
before update on public.match_batting_turns
for each row execute function public.set_updated_at();

alter table public.match_batting_turns enable row level security;

grant select on public.match_batting_turns to anon, authenticated;

create policy "public can read batting turns for live scoring"
on public.match_batting_turns
for select
using (true);

create or replace function public.refresh_match_batting_turn(target_batting_turn_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  turn_record public.match_batting_turns%rowtype;
  legal_ball_count integer;
  has_wicket boolean;
begin
  select mbt.* into turn_record
  from public.match_batting_turns mbt
  where mbt.id = target_batting_turn_id
  for update;

  if turn_record.id is null then
    raise exception 'batting turn not found';
  end if;

  select
    count(*) filter (where md.delivery_type = 'legal')::integer,
    coalesce(bool_or(md.is_wicket), false)
  into legal_ball_count, has_wicket
  from public.match_deliveries md
  where md.batting_turn_id = target_batting_turn_id;

  if has_wicket then
    update public.match_batting_turns
    set status = 'ended',
        end_reason = 'dismissed',
        ended_at = coalesce(ended_at, now()),
        updated_at = now()
    where id = target_batting_turn_id;
  elsif turn_record.phase = 'initial' and legal_ball_count >= 6 then
    update public.match_batting_turns
    set status = 'ended',
        end_reason = 'six_balls',
        ended_at = coalesce(ended_at, now()),
        updated_at = now()
    where id = target_batting_turn_id;
  else
    update public.match_batting_turns
    set status = 'active',
        end_reason = null,
        ended_at = null,
        updated_at = now()
    where id = target_batting_turn_id;
  end if;
end;
$$;

revoke all on function public.refresh_match_batting_turn(uuid) from public, anon, authenticated;

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

  select case when exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.batting_season_team_id
      and not exists (
        select 1
        from public.match_batting_turns mbt
        where mbt.innings_id = target_innings_id
          and mbt.batter_season_roster_id = ml.season_roster_id
          and mbt.phase = 'initial'
          and mbt.status = 'ended'
          and mbt.end_reason in ('six_balls', 'dismissed')
      )
  ) then 'initial' else 'flexible' end
  into batting_phase;

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

create or replace function public.validate_match_over_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  match_record public.matches%rowtype;
  existing_bowling_overs integer;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = new.innings_id;

  select m.* into match_record
  from public.matches m
  where m.id = innings_record.match_id;

  if new.over_number > innings_record.overs_limit then
    raise exception 'over number exceeds the innings limit';
  end if;

  if new.batting_slot_season_roster_id is not null and not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_record.id
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = new.batting_slot_season_roster_id
  ) then
    raise exception 'legacy batting slot player must be in the batting lineup';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_record.id
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.bowler_season_roster_id
  ) then
    raise exception 'bowler must be in the bowling lineup';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_record.id
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.wicketkeeper_season_roster_id
  ) then
    raise exception 'wicketkeeper must be in the bowling lineup';
  end if;

  select count(*)::integer into existing_bowling_overs
  from public.match_over_assignments moa
  where moa.innings_id = new.innings_id
    and moa.bowler_season_roster_id = new.bowler_season_roster_id
    and moa.id <> new.id;

  if existing_bowling_overs >= innings_record.max_overs_per_player then
    raise exception 'bowler exceeds the season over limit';
  end if;

  return new;
end;
$$;

create or replace function public.set_match_over_assignment(
  target_innings_id uuid,
  target_over_number integer,
  target_bowler_season_roster_id uuid,
  target_wicketkeeper_season_roster_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  assignment_id_value uuid;
  previous_assignment_id uuid;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = target_innings_id
  for update;

  if innings_record.id is null or innings_record.status <> 'live' then
    raise exception 'innings is not live';
  end if;

  if target_over_number < 1 or target_over_number > innings_record.overs_limit then
    raise exception 'over number is outside the innings limit';
  end if;

  if target_over_number > 1 then
    select moa.id into previous_assignment_id
    from public.match_over_assignments moa
    where moa.innings_id = target_innings_id
      and moa.over_number = target_over_number - 1;

    if previous_assignment_id is null then
      raise exception 'the previous over must be assigned first';
    end if;

    if (
      select count(*)
      from public.match_deliveries md
      where md.over_assignment_id = previous_assignment_id
        and md.delivery_type = 'legal'
    ) < innings_record.balls_per_over then
      raise exception 'the previous over must contain six legal balls';
    end if;
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    where moa.innings_id = target_innings_id
      and moa.over_number = target_over_number
  ) then
    raise exception 'an over cannot be reassigned after scoring has started';
  end if;

  insert into public.match_over_assignments (
    innings_id,
    over_number,
    batting_slot_season_roster_id,
    bowler_season_roster_id,
    wicketkeeper_season_roster_id
  ) values (
    target_innings_id,
    target_over_number,
    null,
    target_bowler_season_roster_id,
    target_wicketkeeper_season_roster_id
  )
  on conflict (innings_id, over_number) do update
  set batting_slot_season_roster_id = null,
      bowler_season_roster_id = excluded.bowler_season_roster_id,
      wicketkeeper_season_roster_id = excluded.wicketkeeper_season_roster_id,
      updated_at = now()
  returning id into assignment_id_value;

  return assignment_id_value;
end;
$$;

grant execute on function public.set_match_over_assignment(uuid, integer, uuid, uuid) to anon, authenticated;

create or replace function public.validate_match_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
  batting_turn_record public.match_batting_turns%rowtype;
  match_id_value uuid;
begin
  select moa.* into assignment_record
  from public.match_over_assignments moa
  where moa.id = new.over_assignment_id;

  if assignment_record.innings_id is distinct from new.innings_id then
    raise exception 'delivery innings must match the over assignment';
  end if;

  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = new.innings_id;

  match_id_value := innings_record.match_id;

  select mbt.* into batting_turn_record
  from public.match_batting_turns mbt
  where mbt.id = new.batting_turn_id;

  if batting_turn_record.id is null
    or batting_turn_record.innings_id is distinct from new.innings_id
    or batting_turn_record.status <> 'active' then
    raise exception 'delivery requires the active batting turn';
  end if;

  if new.striker_season_roster_id is distinct from batting_turn_record.batter_season_roster_id then
    raise exception 'delivery striker must match the active batting turn';
  end if;

  if new.non_striker_season_roster_id is not null then
    raise exception 'non-striker is not used in this scoring format';
  end if;

  if new.bowler_season_roster_id is distinct from assignment_record.bowler_season_roster_id then
    raise exception 'delivery bowler must match the over assignment';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = new.striker_season_roster_id
  ) then
    raise exception 'striker must belong to the batting lineup';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.bowler_season_roster_id
  ) then
    raise exception 'bowler must belong to the bowling lineup';
  end if;

  if new.fielder_season_roster_id is not null and not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.fielder_season_roster_id
  ) then
    raise exception 'fielder must belong to the bowling lineup';
  end if;

  if new.delivery_type = 'legal' and new.extra_runs <> 0 then
    raise exception 'legal deliveries cannot have extras in this scoring model';
  end if;

  if new.delivery_type in ('wide', 'no_ball') and new.extra_runs < 1 then
    raise exception 'wides and no-balls must record at least one extra run';
  end if;

  if new.delivery_type = 'no_ball' and new.batter_runs not in (0, 1, 2, 4, 6) then
    raise exception 'no-balls support 0, 1, 2, 4, or 6 batter runs';
  end if;

  if new.delivery_type = 'dead_ball' and (new.batter_runs <> 0 or new.extra_runs <> 0 or new.is_wicket) then
    raise exception 'dead balls cannot score runs or wickets';
  end if;

  if new.is_wicket and new.dismissed_season_roster_id is distinct from new.striker_season_roster_id then
    raise exception 'dismissed player must be the striker';
  end if;

  if new.dismissal_type = 'stumped'
    and new.fielder_season_roster_id is distinct from assignment_record.wicketkeeper_season_roster_id then
    raise exception 'stumpings must be credited to the wicketkeeper';
  end if;

  if new.dismissal_type in ('caught', 'stumped', 'run_out') and new.fielder_season_roster_id is null then
    raise exception 'this dismissal requires a fielder';
  end if;

  if new.dismissal_type in ('bowled', 'hit_wicket') and new.fielder_season_roster_id is not null then
    raise exception 'this dismissal cannot have a fielder';
  end if;

  return new;
end;
$$;

create or replace function public.record_match_delivery(
  target_over_assignment_id uuid,
  target_striker_season_roster_id uuid,
  target_non_striker_season_roster_id uuid,
  target_delivery_type text,
  target_batter_runs integer default 0,
  target_extra_runs integer default 0,
  target_is_wicket boolean default false,
  target_dismissed_season_roster_id uuid default null,
  target_dismissal_type text default null,
  target_fielder_season_roster_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
  batting_turn_record public.match_batting_turns%rowtype;
  match_status text;
  current_over_legal_balls integer;
  innings_legal_balls integer;
  delivery_id_value uuid;
  sequence_value integer;
begin
  select moa.* into assignment_record
  from public.match_over_assignments moa
  where moa.id = target_over_assignment_id
  for update;

  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = assignment_record.innings_id
  for update;

  select status into match_status
  from public.matches
  where id = innings_record.match_id;

  if innings_record.status <> 'live' or match_status <> 'live' then
    raise exception 'match innings is not live';
  end if;

  select mbt.* into batting_turn_record
  from public.match_batting_turns mbt
  where mbt.innings_id = innings_record.id
    and mbt.status = 'active'
  for update;

  if batting_turn_record.id is null then
    raise exception 'choose the next batsman before recording a delivery';
  end if;

  if target_striker_season_roster_id is distinct from batting_turn_record.batter_season_roster_id then
    raise exception 'delivery striker must match the active batting turn';
  end if;

  if target_non_striker_season_roster_id is not null then
    raise exception 'non-striker is not used in this scoring format';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    where moa.innings_id = innings_record.id
      and moa.over_number > assignment_record.over_number
  ) then
    raise exception 'a later over has already been scored';
  end if;

  if assignment_record.over_number > 1 and exists (
    select 1
    from public.match_over_assignments previous
    where previous.innings_id = innings_record.id
      and previous.over_number = assignment_record.over_number - 1
      and (
        select count(*)
        from public.match_deliveries md
        where md.over_assignment_id = previous.id
          and md.delivery_type = 'legal'
      ) < innings_record.balls_per_over
  ) then
    raise exception 'the previous over must contain six legal balls';
  end if;

  select count(*)::integer into current_over_legal_balls
  from public.match_deliveries md
  where md.over_assignment_id = assignment_record.id
    and md.delivery_type = 'legal';

  if current_over_legal_balls >= innings_record.balls_per_over then
    raise exception 'this over already contains six legal balls';
  end if;

  select count(*) filter (where md.delivery_type = 'legal')::integer
  into innings_legal_balls
  from public.match_deliveries md
  where md.innings_id = innings_record.id;

  if innings_legal_balls >= innings_record.legal_balls_limit then
    raise exception 'the innings legal-ball limit has been reached';
  end if;

  if target_delivery_type not in ('legal', 'wide', 'no_ball', 'dead_ball') then
    raise exception 'invalid delivery type';
  end if;

  if target_delivery_type = 'legal' and target_extra_runs <> 0 then
    raise exception 'legal deliveries cannot have extras';
  end if;

  if target_delivery_type in ('wide', 'no_ball') and target_extra_runs < 1 then
    raise exception 'wides and no-balls require an extra run';
  end if;

  if target_delivery_type = 'no_ball' and target_batter_runs not in (0, 1, 2, 4, 6) then
    raise exception 'no-balls support 0, 1, 2, 4, or 6 batter runs';
  end if;

  if target_delivery_type = 'dead_ball'
    and (target_batter_runs <> 0 or target_extra_runs <> 0 or target_is_wicket) then
    raise exception 'dead balls cannot score runs or wickets';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    where md.innings_id = innings_record.id
      and md.dismissed_season_roster_id = target_striker_season_roster_id
  ) then
    raise exception 'a dismissed player cannot return to the crease';
  end if;

  select coalesce(max(delivery_sequence), 0) + 1 into sequence_value
  from public.match_deliveries md
  where md.innings_id = innings_record.id;

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
    innings_record.id,
    assignment_record.id,
    batting_turn_record.id,
    sequence_value,
    case when target_delivery_type = 'legal' then current_over_legal_balls + 1 else null end,
    target_striker_season_roster_id,
    null,
    assignment_record.bowler_season_roster_id,
    target_delivery_type,
    target_batter_runs,
    target_extra_runs,
    target_is_wicket,
    target_dismissed_season_roster_id,
    target_dismissal_type,
    target_fielder_season_roster_id
  )
  returning id into delivery_id_value;

  perform public.refresh_match_batting_turn(batting_turn_record.id);

  return delivery_id_value;
end;
$$;

create or replace function public.update_current_over_delivery(
  target_delivery_id uuid,
  target_striker_season_roster_id uuid,
  target_non_striker_season_roster_id uuid,
  target_delivery_type text,
  target_batter_runs integer default 0,
  target_extra_runs integer default 0,
  target_is_wicket boolean default false,
  target_dismissed_season_roster_id uuid default null,
  target_dismissal_type text default null,
  target_fielder_season_roster_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  delivery_record public.match_deliveries%rowtype;
  batting_turn_record public.match_batting_turns%rowtype;
  current_over_number integer;
begin
  select md.* into delivery_record
  from public.match_deliveries md
  where md.id = target_delivery_id
  for update;

  if delivery_record.id is null or delivery_record.batting_turn_id is null then
    raise exception 'delivery not found or has no batting turn';
  end if;

  select max(moa.over_number) into current_over_number
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = delivery_record.innings_id;

  if (select status from public.match_innings where id = delivery_record.innings_id) <> 'live'
    or current_over_number <> (
      select moa.over_number
      from public.match_over_assignments moa
      where moa.id = delivery_record.over_assignment_id
    ) then
    raise exception 'only deliveries from the current over can be edited';
  end if;

  select mbt.* into batting_turn_record
  from public.match_batting_turns mbt
  where mbt.id = delivery_record.batting_turn_id
  for update;

  if exists (
    select 1
    from public.match_batting_turns later
    where later.innings_id = batting_turn_record.innings_id
      and later.turn_number > batting_turn_record.turn_number
  ) then
    raise exception 'a delivery cannot be edited after the next batsman has started';
  end if;

  if target_striker_season_roster_id is distinct from batting_turn_record.batter_season_roster_id
    or target_non_striker_season_roster_id is not null then
    raise exception 'delivery batsman must match the batting turn';
  end if;

  update public.match_batting_turns
  set status = 'active',
      end_reason = null,
      ended_at = null,
      updated_at = now()
  where id = batting_turn_record.id;

  update public.match_deliveries
  set striker_season_roster_id = target_striker_season_roster_id,
      non_striker_season_roster_id = null,
      delivery_type = target_delivery_type,
      batter_runs = target_batter_runs,
      extra_runs = target_extra_runs,
      is_wicket = target_is_wicket,
      dismissed_season_roster_id = target_dismissed_season_roster_id,
      dismissal_type = target_dismissal_type,
      fielder_season_roster_id = target_fielder_season_roster_id,
      updated_at = now()
  where id = target_delivery_id;

  perform public.resequence_match_over(delivery_record.over_assignment_id);
  perform public.refresh_match_batting_turn(batting_turn_record.id);

  return target_delivery_id;
end;
$$;

create or replace function public.delete_current_over_delivery(target_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  delivery_record public.match_deliveries%rowtype;
  batting_turn_record public.match_batting_turns%rowtype;
  current_over_number integer;
  delivery_over_number integer;
begin
  select md.* into delivery_record
  from public.match_deliveries md
  where md.id = target_delivery_id
  for update;

  if delivery_record.id is null or delivery_record.batting_turn_id is null then
    raise exception 'delivery not found or has no batting turn';
  end if;

  select moa.over_number into delivery_over_number
  from public.match_over_assignments moa
  where moa.id = delivery_record.over_assignment_id;

  select max(moa.over_number) into current_over_number
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = delivery_record.innings_id;

  if delivery_over_number <> current_over_number then
    raise exception 'only deliveries from the current over can be deleted';
  end if;

  if (select status from public.match_innings where id = delivery_record.innings_id) <> 'live' then
    raise exception 'only live innings can be corrected';
  end if;

  select mbt.* into batting_turn_record
  from public.match_batting_turns mbt
  where mbt.id = delivery_record.batting_turn_id
  for update;

  if exists (
    select 1
    from public.match_batting_turns later
    where later.innings_id = batting_turn_record.innings_id
      and later.turn_number > batting_turn_record.turn_number
  ) then
    raise exception 'a delivery cannot be deleted after the next batsman has started';
  end if;

  update public.match_batting_turns
  set status = 'active',
      end_reason = null,
      ended_at = null,
      updated_at = now()
  where id = batting_turn_record.id;

  delete from public.match_deliveries where id = target_delivery_id;
  perform public.resequence_match_over(delivery_record.over_assignment_id);
  perform public.refresh_match_batting_turn(batting_turn_record.id);
end;
$$;

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
  next_innings_id uuid;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = target_innings_id
  for update;

  if innings_record.status <> 'live' then
    raise exception 'innings is already completed';
  end if;

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
  end if;

  update public.match_batting_turns
  set status = 'ended',
      end_reason = 'innings_end',
      ended_at = now(),
      updated_at = now()
  where innings_id = target_innings_id
    and status = 'active';

  update public.match_innings
  set status = 'completed',
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

grant execute on function public.record_match_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.update_current_over_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.delete_current_over_delivery(uuid) to anon, authenticated;
grant execute on function public.complete_match_innings(uuid) to anon, authenticated;
grant execute on function public.get_match_scoring_state(uuid) to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'match_batting_turns'
    ) then
    alter publication supabase_realtime add table public.match_batting_turns;
  end if;
end;
$$;
