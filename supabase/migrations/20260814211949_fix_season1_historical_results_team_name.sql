-- The source archive used "Short-Pitch Sharks", while the canonical team
-- record uses "Short Pitch Sharks". Complete the one-time import by resolving
-- that historical alias to the existing team record.

with source_rows (
  source_match_id, match_date, home_team_name, home_runs, home_wickets,
  away_team_name, away_runs, away_wickets, winner_team_name,
  match_type, match_type_label, player_of_match_name
) as (
  values
    ('Vsp493F1awoUZFoh34qx', '2026-07-18T13:30:00.000Z'::timestamptz, 'Jersey Indians', 35, 3, 'Short-Pitch Sharks', 34, 5, 'Jersey Indians', 'final', 'Final', 'Prashant Varma'),
    ('PUYX1005WJAxwb7pfpbr', '2026-07-18T12:45:00.000Z'::timestamptz, 'Jersey Warriors', 39, 4, 'Short-Pitch Sharks', 48, 5, 'Short-Pitch Sharks', 'qualifier2', 'Qualifier 2', 'Hardik Shah'),
    ('65JDL3me6SWYEqB3ejd0', '2026-07-18T12:00:00.000Z'::timestamptz, 'Dhurandhars Revenge', 31, 4, 'Short-Pitch Sharks', 54, 2, 'Short-Pitch Sharks', 'eliminator', 'Eliminator', 'Sundararajan Velayutham'),
    ('dwWuSaaDYaCxQjSc4rI4', '2026-07-12T12:15:00.000Z'::timestamptz, 'Jersey Warriors', 47, 4, 'Short-Pitch Sharks', 29, 6, 'Jersey Warriors', 'league', 'League', 'Sanjay Solanki'),
    ('5uPKKMzgf8G6tYHtA37c', '2026-07-11T13:45:00.000Z'::timestamptz, 'Short-Pitch Sharks', 31, 3, 'Dhurandhars Revenge', 50, 6, 'Dhurandhars Revenge', 'league', 'League', 'Shubham Pandey'),
    ('8DSJZt2W0YR2RcxWRN4t', '2026-06-27T13:45:00.000Z'::timestamptz, 'Jersey Indians', 38, 5, 'Short-Pitch Sharks', 29, 6, 'Jersey Indians', 'league', 'League', 'Swapnil Shah'),
    ('3RC8wS1vR9y4MBmYWC5u', '2026-06-27T12:15:00.000Z'::timestamptz, 'Shadow Strikers', 46, 5, 'Short-Pitch Sharks', 52, 5, 'Short-Pitch Sharks', 'league', 'League', 'Sundararajan Velayutham'),
    ('bsTCVOJ8ppM5zKKWUgwV', '2026-06-13T12:15:00.000Z'::timestamptz, 'Game Changers', 24, 6, 'Short-Pitch Sharks', 28, 1, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('VJuRAJ6Ya8vS2jED9EcO', '2026-06-13T11:45:00.000Z'::timestamptz, 'Short-Pitch Sharks', 31, 2, 'Shadow Strikers', 27, 5, 'Short-Pitch Sharks', 'league', 'League', 'Supreeth Premkumar'),
    ('bvCepCfqXZ9OE7fw4pNh', '2026-06-06T13:00:00.000Z'::timestamptz, 'Short-Pitch Sharks', 37, 5, 'Jersey Indians', 51, 3, 'Jersey Indians', 'league', 'League', 'Swapnil Shah'),
    ('kKMIJC3o3IC5NnjLYz11', '2026-06-06T12:00:00.000Z'::timestamptz, 'Short-Pitch Sharks', 48, 3, 'Power Strikers', 47, 3, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('JzZtwizNL9QQ00i1RJOC', '2026-05-30T13:30:00.000Z'::timestamptz, 'Power Strikers', 38, 5, 'Short-Pitch Sharks', 37, 1, 'Power Strikers', 'league', 'League', 'Mandar Patki'),
    ('LrDwu4w3oaSo7CitczUL', '2026-05-23T13:30:00.000Z'::timestamptz, 'Dhurandhars Revenge', 29, 4, 'Short-Pitch Sharks', 30, 4, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('sRppuOO2stgvL1O65o23', '2026-05-23T12:30:00.000Z'::timestamptz, 'Short-Pitch Sharks', 52, 4, 'Game Changers', 52, 3, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('A8ihPtKewPRzynSqqw2y', '2026-05-16T13:30:00.000Z'::timestamptz, 'Short-Pitch Sharks', 31, 6, 'Jersey Warriors', 34, 0, 'Jersey Warriors', 'league', 'League', 'Santosh Naidu')
),
season_context as (
  select s.id as season_id, s.league_id
  from public.seasons s
  join public.leagues l on l.id = s.league_id
  where s.name = 'Season 1'
    and l.slug = 'box-cricket-league'
)
insert into public.legacy_match_results (
  season_id,
  source,
  source_match_id,
  match_date,
  home_season_team_id,
  home_team_name,
  home_runs,
  home_wickets,
  away_season_team_id,
  away_team_name,
  away_runs,
  away_wickets,
  winner_season_team_id,
  match_type,
  match_type_label,
  player_of_match_name,
  captured_at
)
select
  sc.season_id,
  'firestore.archive.season1Matches',
  r.source_match_id,
  r.match_date,
  home_st.id,
  home_team.name,
  r.home_runs,
  r.home_wickets,
  away_st.id,
  away_team.name,
  r.away_runs,
  r.away_wickets,
  winner_st.id,
  r.match_type,
  r.match_type_label,
  r.player_of_match_name,
  '2026-07-21T19:29:39.850Z'::timestamptz
from source_rows r
join season_context sc on true
join public.teams home_team
  on home_team.league_id = sc.league_id
 and home_team.name = case when r.home_team_name = 'Short-Pitch Sharks' then 'Short Pitch Sharks' else r.home_team_name end
join public.season_teams home_st
  on home_st.season_id = sc.season_id
 and home_st.team_id = home_team.id
join public.teams away_team
  on away_team.league_id = sc.league_id
 and away_team.name = case when r.away_team_name = 'Short-Pitch Sharks' then 'Short Pitch Sharks' else r.away_team_name end
join public.season_teams away_st
  on away_st.season_id = sc.season_id
 and away_st.team_id = away_team.id
join public.teams winner_team
  on winner_team.league_id = sc.league_id
 and winner_team.name = case when r.winner_team_name = 'Short-Pitch Sharks' then 'Short Pitch Sharks' else r.winner_team_name end
join public.season_teams winner_st
  on winner_st.season_id = sc.season_id
 and winner_st.team_id = winner_team.id
on conflict (season_id, source, source_match_id) do update set
  match_date = excluded.match_date,
  home_season_team_id = excluded.home_season_team_id,
  home_team_name = excluded.home_team_name,
  home_runs = excluded.home_runs,
  home_wickets = excluded.home_wickets,
  away_season_team_id = excluded.away_season_team_id,
  away_team_name = excluded.away_team_name,
  away_runs = excluded.away_runs,
  away_wickets = excluded.away_wickets,
  winner_season_team_id = excluded.winner_season_team_id,
  match_type = excluded.match_type,
  match_type_label = excluded.match_type_label,
  player_of_match_name = excluded.player_of_match_name,
  captured_at = excluded.captured_at,
  updated_at = now();

with season_context as (
  select s.id as season_id, s.league_id
  from public.seasons s
  join public.leagues l on l.id = s.league_id
  where s.name = 'Season 1'
    and l.slug = 'box-cricket-league'
)
update public.legacy_match_results lmr
set home_team_name = home_team.name,
    away_team_name = away_team.name,
    updated_at = now()
from season_context sc
cross join public.teams home_team
cross join public.teams away_team
where lmr.season_id = sc.season_id
  and home_team.id = lmr.home_season_team_id
  and away_team.id = lmr.away_season_team_id;

with season_context as (
  select s.id as season_id, s.league_id
  from public.seasons s
  join public.leagues l on l.id = s.league_id
  where s.name = 'Season 1'
    and l.slug = 'box-cricket-league'
)
insert into public.legacy_season_standings (
  season_id,
  season_team_id,
  source,
  matches_played,
  wins,
  losses,
  draws,
  points,
  runs_for,
  balls_faced,
  runs_against,
  balls_bowled,
  net_run_rate,
  captured_at
)
select
  sc.season_id,
  st.id,
  'firestore.archive.season1Standings',
  15,
  8,
  7,
  0,
  16,
  571,
  503,
  588,
  519,
  0.013445339523553201::numeric,
  '2026-07-25T17:47:15.359Z'::timestamptz
from season_context sc
join public.teams t
  on t.league_id = sc.league_id
 and t.name = 'Short Pitch Sharks'
join public.season_teams st
  on st.season_id = sc.season_id
 and st.team_id = t.id
on conflict (season_id, source, season_team_id) do update set
  matches_played = excluded.matches_played,
  wins = excluded.wins,
  losses = excluded.losses,
  draws = excluded.draws,
  points = excluded.points,
  runs_for = excluded.runs_for,
  balls_faced = excluded.balls_faced,
  runs_against = excluded.runs_against,
  balls_bowled = excluded.balls_bowled,
  net_run_rate = excluded.net_run_rate,
  captured_at = excluded.captured_at,
  updated_at = now();
