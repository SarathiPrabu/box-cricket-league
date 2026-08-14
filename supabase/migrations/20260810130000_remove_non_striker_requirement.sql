alter table public.match_deliveries
  alter column non_striker_season_roster_id drop not null;

alter table public.match_deliveries
  drop constraint if exists match_deliveries_players_distinct;

alter table public.match_deliveries
  add constraint match_deliveries_players_distinct check (
    non_striker_season_roster_id is null
    or striker_season_roster_id <> non_striker_season_roster_id
  );

alter table public.match_deliveries
  drop constraint if exists match_deliveries_no_ball_batter_runs_check;

alter table public.match_deliveries
  add constraint match_deliveries_no_ball_batter_runs_check check (
    delivery_type <> 'no_ball'
    or batter_runs in (0, 1, 2, 4, 6)
  );

create or replace function public.validate_match_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
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

  select match_id into match_id_value
  from public.match_innings
  where id = new.innings_id;

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

  if new.non_striker_season_roster_id is not null and not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = new.non_striker_season_roster_id
  ) then
    raise exception 'non-striker must belong to the batting lineup';
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
