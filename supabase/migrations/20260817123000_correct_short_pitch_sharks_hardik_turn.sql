-- Correct the live Short Pitch Sharks innings after the scorer kept Supreeth
-- batting from 4.6 through the dismissal at 6.5 instead of switching to Hardik.
alter table public.match_deliveries
  disable trigger match_deliveries_prevent_confirmed_over_change;

do $$
declare
  target_match_id uuid;
  target_innings_id uuid;
  hardik_roster_id uuid;
  supreeth_roster_id uuid;
  supreeth_turn_id uuid;
  hardik_turn_id uuid;
begin
  select m.id
  into target_match_id
  from public.matches m
  join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
  join public.teams home_team on home_team.id = home_season_team.team_id
  join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
  join public.teams away_team on away_team.id = away_season_team.team_id
  where m.status = 'live'
    and home_team.name = 'Short Pitch Sharks'
    and away_team.name = 'Titans';

  if target_match_id is null then
    raise exception 'live Short Pitch Sharks vs Titans match not found';
  end if;

  select mi.id
  into target_innings_id
  from public.match_innings mi
  where mi.match_id = target_match_id
    and mi.innings_number = 1
    and mi.status = 'live';

  select ml.season_roster_id
  into hardik_roster_id
  from public.match_lineups ml
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  where ml.match_id = target_match_id
    and ml.season_team_id = (select batting_season_team_id from public.match_innings where id = target_innings_id)
    and p.display_name = 'Hardik Shah';

  select ml.season_roster_id
  into supreeth_roster_id
  from public.match_lineups ml
  join public.season_rosters sr on sr.id = ml.season_roster_id
  join public.players p on p.id = sr.player_id
  where ml.match_id = target_match_id
    and ml.season_team_id = (select batting_season_team_id from public.match_innings where id = target_innings_id)
    and p.display_name = 'Supreeth Premkumar';

  select mbt.id
  into supreeth_turn_id
  from public.match_batting_turns mbt
  where mbt.innings_id = target_innings_id
    and mbt.batter_season_roster_id = supreeth_roster_id
    and mbt.phase = 'flexible'
    and exists (
      select 1
      from public.match_deliveries md
      join public.match_over_assignments moa on moa.id = md.over_assignment_id
      where md.batting_turn_id = mbt.id
        and moa.over_number = 4
        and md.legal_ball_number = 6
    );

  select mbt.id
  into hardik_turn_id
  from public.match_batting_turns mbt
  where mbt.innings_id = target_innings_id
    and mbt.batter_season_roster_id = hardik_roster_id
    and mbt.phase = 'flexible'
    and mbt.status = 'active'
    and not exists (
      select 1 from public.match_deliveries md where md.batting_turn_id = mbt.id
    );

  if supreeth_turn_id is null or hardik_turn_id is null then
    raise exception 'expected Supreeth flexible turn and empty active Hardik turn were not found';
  end if;

  update public.match_batting_turns
  set status = 'ended',
      end_reason = 'switched',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where id = supreeth_turn_id;

  update public.match_deliveries md
  set striker_season_roster_id = hardik_roster_id,
      batting_turn_id = hardik_turn_id,
      dismissed_season_roster_id = case when md.is_wicket then hardik_roster_id else null end,
      updated_at = now()
  from public.match_over_assignments moa
  where md.over_assignment_id = moa.id
    and md.innings_id = target_innings_id
    and moa.over_number between 4 and 6
    and md.delivery_sequence between 30 and 41;

  update public.match_batting_turns
  set status = 'ended',
      end_reason = 'dismissed',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where id = hardik_turn_id;
end;
$$;

alter table public.match_deliveries
  enable trigger match_deliveries_prevent_confirmed_over_change;
