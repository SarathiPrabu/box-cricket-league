begin;

do $$
declare
  expected_player_id uuid := 'd6f96a62-9291-70de-7577-db91ff513bf5'::uuid;
  expected_season_id uuid := 'f5af40e3-953b-431e-93ba-233765ee02c0'::uuid;
  expected_roster_id uuid := 'd1b5f1be-626d-4836-83b2-46155fbb6693'::uuid;
  indians_season_team_id uuid := '993dbdf8-14d4-49da-bb8c-669a3f64e1cd'::uuid;
  warriors_season_team_id uuid := 'b62863e8-a4aa-425c-a8f0-67ef89cc5dbf'::uuid;
  current_roster record;
  reference_count integer;
begin
  select sr.id, sr.season_team_id, sr.season_id, sr.player_id
  into current_roster
  from public.season_rosters sr
  where sr.id = expected_roster_id;

  if not found
     or current_roster.player_id <> expected_player_id
     or current_roster.season_id <> expected_season_id
     or current_roster.season_team_id <> indians_season_team_id then
    raise exception 'unexpected Sumit Gadgilwar Season 2 roster state';
  end if;

  if not exists (
    select 1
    from public.season_teams st
    join public.seasons s on s.id = st.season_id
    join public.teams t on t.id = st.team_id
    where st.id = warriors_season_team_id
      and st.season_id = expected_season_id
      and t.name = 'Jersey Warriors'
  ) then
    raise exception 'Season 2 Jersey Warriors roster target not found';
  end if;

  select count(*) into reference_count
  from (
    select 1 from public.match_lineups where season_roster_id = expected_roster_id
    union all
    select 1 from public.match_staff where season_roster_id = expected_roster_id
    union all
    select 1 from public.legacy_season_player_stats where season_roster_id = expected_roster_id
    union all
    select 1 from public.match_batting_turns where batter_season_roster_id = expected_roster_id
    union all
    select 1 from public.match_over_assignments
      where batting_slot_season_roster_id = expected_roster_id
         or bowler_season_roster_id = expected_roster_id
         or wicketkeeper_season_roster_id = expected_roster_id
    union all
    select 1 from public.match_deliveries
      where striker_season_roster_id = expected_roster_id
         or non_striker_season_roster_id = expected_roster_id
         or bowler_season_roster_id = expected_roster_id
         or dismissed_season_roster_id = expected_roster_id
         or fielder_season_roster_id = expected_roster_id
  ) roster_references;

  if reference_count <> 0 then
    raise exception 'Sumit Gadgilwar roster is referenced by match data';
  end if;

  update public.season_rosters
  set season_team_id = warriors_season_team_id
  where id = expected_roster_id
    and player_id = expected_player_id
    and season_id = expected_season_id
    and season_team_id = indians_season_team_id;

  if not found then
    raise exception 'Sumit Gadgilwar roster update did not affect exactly the expected row';
  end if;
end
$$;

commit;
