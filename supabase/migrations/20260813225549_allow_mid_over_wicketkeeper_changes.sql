-- Allow the active wicketkeeper to change during an unconfirmed over without
-- changing the bowler or rewriting fielder credits on recorded deliveries.

create or replace function public.change_current_over_wicketkeeper(
  target_over_assignment_id uuid,
  target_wicketkeeper_season_roster_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
begin
  select moa.* into assignment_record
  from public.match_over_assignments moa
  where moa.id = target_over_assignment_id
  for update;

  if assignment_record.id is null then
    raise exception 'over assignment not found';
  end if;

  if assignment_record.confirmed_at is not null then
    raise exception 'a confirmed over is locked';
  end if;

  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = assignment_record.innings_id
  for update;

  if innings_record.status <> 'live' then
    raise exception 'only a live innings wicketkeeper can be changed';
  end if;

  if exists (
    select 1
    from public.match_over_assignments later_assignment
    where later_assignment.innings_id = assignment_record.innings_id
      and later_assignment.over_number > assignment_record.over_number
  ) then
    raise exception 'only the current over wicketkeeper can be changed';
  end if;

  if target_wicketkeeper_season_roster_id = assignment_record.bowler_season_roster_id then
    raise exception 'the bowler cannot keep wicket in the same over';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = target_wicketkeeper_season_roster_id
  ) then
    raise exception 'wicketkeeper must be in the bowling lineup';
  end if;

  update public.match_over_assignments
  set wicketkeeper_season_roster_id = target_wicketkeeper_season_roster_id,
      updated_at = now()
  where id = target_over_assignment_id;

  return target_over_assignment_id;
end;
$$;

revoke all on function public.change_current_over_wicketkeeper(uuid, uuid) from public;
grant execute on function public.change_current_over_wicketkeeper(uuid, uuid) to anon, authenticated;

comment on function public.change_current_over_wicketkeeper(uuid, uuid) is
  'Changes only the wicketkeeper for the current unconfirmed over.';
