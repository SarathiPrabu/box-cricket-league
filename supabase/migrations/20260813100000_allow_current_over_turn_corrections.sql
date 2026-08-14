-- Allow scorers to correct any delivery in the actively scored over, including
-- deliveries from an earlier batting turn. A correction may not invalidate a
-- batting turn after a later batsman has already started.

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
  active_turn_record public.match_batting_turns%rowtype;
  current_over_number integer;
  has_later_turn boolean;
  legal_ball_count integer;
  has_wicket boolean;
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

  if target_striker_season_roster_id is distinct from batting_turn_record.batter_season_roster_id
    or target_non_striker_season_roster_id is not null then
    raise exception 'delivery batsman must match the batting turn';
  end if;

  select exists (
    select 1
    from public.match_batting_turns later
    where later.innings_id = batting_turn_record.innings_id
      and later.turn_number > batting_turn_record.turn_number
  ) into has_later_turn;

  if has_later_turn then
    select mbt.* into active_turn_record
    from public.match_batting_turns mbt
    where mbt.innings_id = batting_turn_record.innings_id
      and mbt.status = 'active'
      and mbt.id <> batting_turn_record.id
    for update;

    if active_turn_record.id is not null then
      update public.match_batting_turns
      set status = 'ended',
          end_reason = 'switched',
          ended_at = now(),
          updated_at = now()
      where id = active_turn_record.id;
    end if;
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

  if has_later_turn then
    select
      count(*) filter (where md.delivery_type = 'legal')::integer,
      coalesce(bool_or(md.is_wicket), false)
    into legal_ball_count, has_wicket
    from public.match_deliveries md
    where md.batting_turn_id = batting_turn_record.id;

    if has_wicket and exists (
      select 1
      from public.match_batting_turns later
      where later.innings_id = batting_turn_record.innings_id
        and later.turn_number > batting_turn_record.turn_number
        and later.batter_season_roster_id = batting_turn_record.batter_season_roster_id
    ) then
      raise exception 'correction would dismiss a batsman who appears in a later batting turn';
    end if;

    if batting_turn_record.phase = 'initial' and not has_wicket and legal_ball_count < 6 then
      raise exception 'correction would invalidate the completed batting turn; undo later batting turns first';
    end if;

    update public.match_batting_turns
    set status = 'ended',
        end_reason = case
          when has_wicket then 'dismissed'
          when batting_turn_record.phase = 'initial' then 'six_balls'
          else 'switched'
        end,
        ended_at = coalesce(batting_turn_record.ended_at, now()),
        updated_at = now()
    where id = batting_turn_record.id;

    if active_turn_record.id is not null then
      update public.match_batting_turns
      set status = 'active',
          end_reason = null,
          ended_at = null,
          updated_at = now()
      where id = active_turn_record.id;
    end if;
  else
    perform public.refresh_match_batting_turn(batting_turn_record.id);
  end if;

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
  has_later_turn boolean;
  legal_ball_count integer;
  has_wicket boolean;
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

  select exists (
    select 1
    from public.match_batting_turns later
    where later.innings_id = batting_turn_record.innings_id
      and later.turn_number > batting_turn_record.turn_number
  ) into has_later_turn;

  delete from public.match_deliveries where id = target_delivery_id;
  perform public.resequence_match_over(delivery_record.over_assignment_id);

  if has_later_turn then
    select
      count(*) filter (where md.delivery_type = 'legal')::integer,
      coalesce(bool_or(md.is_wicket), false)
    into legal_ball_count, has_wicket
    from public.match_deliveries md
    where md.batting_turn_id = batting_turn_record.id;

    if batting_turn_record.phase = 'initial' and not has_wicket and legal_ball_count < 6 then
      raise exception 'deletion would invalidate the completed batting turn; undo later batting turns first';
    end if;

    update public.match_batting_turns
    set status = 'ended',
        end_reason = case
          when has_wicket then 'dismissed'
          when batting_turn_record.phase = 'initial' then 'six_balls'
          else 'switched'
        end,
        ended_at = coalesce(batting_turn_record.ended_at, now()),
        updated_at = now()
    where id = batting_turn_record.id;
  else
    perform public.refresh_match_batting_turn(batting_turn_record.id);
  end if;
end;
$$;

grant execute on function public.update_current_over_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.delete_current_over_delivery(uuid) to anon, authenticated;
