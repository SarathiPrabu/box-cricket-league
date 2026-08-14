-- Season 1 has final match summaries and final aggregate standings, but no
-- player-by-player scorecards. Keep this one-time import separate from live
-- scoring tables so historical data is explicit and cannot be mistaken for
-- delivery-derived player statistics.

create table public.legacy_match_results (
  id uuid primary key default extensions.gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  source text not null,
  source_match_id text not null,
  match_date timestamptz not null,
  venue text not null default 'Community Park',
  home_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  home_team_name text not null,
  home_runs integer not null,
  home_wickets integer not null,
  away_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  away_team_name text not null,
  away_runs integer not null,
  away_wickets integer not null,
  winner_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  match_type text not null,
  match_type_label text not null,
  player_of_match_name text,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legacy_match_results_source_unique unique (season_id, source, source_match_id),
  constraint legacy_match_results_distinct_teams check (home_season_team_id <> away_season_team_id),
  constraint legacy_match_results_winner_check check (
    winner_season_team_id in (home_season_team_id, away_season_team_id)
  ),
  constraint legacy_match_results_non_negative check (
    home_runs >= 0
    and home_wickets between 0 and 10
    and away_runs >= 0
    and away_wickets between 0 and 10
  ),
  constraint legacy_match_results_type_check check (
    match_type in ('league', 'qualifier1', 'qualifier2', 'eliminator', 'final')
  )
);

create index legacy_match_results_season_date_idx
  on public.legacy_match_results (season_id, match_date);

create trigger legacy_match_results_set_updated_at
before update on public.legacy_match_results
for each row execute function public.set_updated_at();

alter table public.legacy_match_results enable row level security;

comment on table public.legacy_match_results is
  'One-time historical match summaries imported without player-by-player scorecards.';

create table public.legacy_season_standings (
  id uuid primary key default extensions.gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  season_team_id uuid not null references public.season_teams(id) on delete restrict,
  source text not null,
  matches_played integer not null,
  wins integer not null,
  losses integer not null,
  draws integer not null,
  points integer not null,
  runs_for integer not null,
  balls_faced integer not null,
  runs_against integer not null,
  balls_bowled integer not null,
  net_run_rate numeric not null,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legacy_season_standings_source_unique unique (season_id, source, season_team_id),
  constraint legacy_season_standings_non_negative check (
    matches_played >= 0
    and wins >= 0
    and losses >= 0
    and draws >= 0
    and points >= 0
    and runs_for >= 0
    and balls_faced >= 0
    and runs_against >= 0
    and balls_bowled >= 0
  ),
  constraint legacy_season_standings_record_check check (
    matches_played = wins + losses + draws
    and points = wins * 2 + draws
  )
);

create index legacy_season_standings_season_id_idx
  on public.legacy_season_standings (season_id);

create trigger legacy_season_standings_set_updated_at
before update on public.legacy_season_standings
for each row execute function public.set_updated_at();

alter table public.legacy_season_standings enable row level security;

comment on table public.legacy_season_standings is
  'Captured final standings for seasons whose source has no scorecards.';

with source_rows (
  source_match_id, match_date, home_team_name, home_runs, home_wickets,
  away_team_name, away_runs, away_wickets, winner_team_name,
  match_type, match_type_label, player_of_match_name
) as (
  values
    ('Vsp493F1awoUZFoh34qx', '2026-07-18T13:30:00.000Z'::timestamptz, 'Jersey Indians', 35, 3, 'Short-Pitch Sharks', 34, 5, 'Jersey Indians', 'final', 'Final', 'Prashant Varma'),
    ('PUYX1005WJAxwb7pfpbr', '2026-07-18T12:45:00.000Z'::timestamptz, 'Jersey Warriors', 39, 4, 'Short-Pitch Sharks', 48, 5, 'Short-Pitch Sharks', 'qualifier2', 'Qualifier 2', 'Hardik Shah'),
    ('65JDL3me6SWYEqB3ejd0', '2026-07-18T12:00:00.000Z'::timestamptz, 'Dhurandhars Revenge', 31, 4, 'Short-Pitch Sharks', 54, 2, 'Short-Pitch Sharks', 'eliminator', 'Eliminator', 'Sundararajan Velayutham'),
    ('P5JKwDpWNVkYZwBUKi0p', '2026-07-18T11:30:00.000Z'::timestamptz, 'Jersey Indians', 40, 2, 'Jersey Warriors', 38, 3, 'Jersey Indians', 'qualifier1', 'Qualifier 1', 'Hari S'),
    ('fH4MiICvVLeI0V1L2Sqr', '2026-07-12T13:15:00.000Z'::timestamptz, 'Jersey Indians', 36, 1, 'Power Strikers', 35, 5, 'Jersey Indians', 'league', 'League', 'Swapnil Shah'),
    ('dwWuSaaDYaCxQjSc4rI4', '2026-07-12T12:15:00.000Z'::timestamptz, 'Jersey Warriors', 47, 4, 'Short-Pitch Sharks', 29, 6, 'Jersey Warriors', 'league', 'League', 'Sanjay Solanki'),
    ('syhZEjpwkXknbOnBUjUL', '2026-07-12T12:00:00.000Z'::timestamptz, 'Jersey Warriors', 50, 3, 'Shadow Strikers', 39, 5, 'Jersey Warriors', 'league', 'League', 'Sanjay Solanki'),
    ('5uPKKMzgf8G6tYHtA37c', '2026-07-11T13:45:00.000Z'::timestamptz, 'Short-Pitch Sharks', 31, 3, 'Dhurandhars Revenge', 50, 6, 'Dhurandhars Revenge', 'league', 'League', 'Shubham Pandey'),
    ('7RSRfMDissr8ezbHIuad', '2026-07-11T13:15:00.000Z'::timestamptz, 'Jersey Indians', 52, 3, 'Game Changers', 38, 6, 'Jersey Indians', 'league', 'League', 'Swapnil Shah'),
    ('fhvQ0hDALwpZloe0hPAj', '2026-07-11T12:45:00.000Z'::timestamptz, 'Power Strikers', 49, 4, 'Shadow Strikers', 45, 2, 'Power Strikers', 'league', 'League', 'Sagar Parmar'),
    ('G7hQswE17dexdLy0QTrV', '2026-07-11T12:15:00.000Z'::timestamptz, 'Game Changers', 43, 5, 'Dhurandhars Revenge', 40, 6, 'Game Changers', 'league', 'League', 'Sumit Lole'),
    ('aOg5GWdHVqDOt6soQspN', '2026-07-11T11:45:00.000Z'::timestamptz, 'Power Strikers', 31, 3, 'Jersey Indians', 43, 3, 'Jersey Indians', 'league', 'League', 'Hari S'),
    ('ywn6UaGpxggUcinvhe80', '2026-06-27T14:15:00.000Z'::timestamptz, 'Shadow Strikers', 54, 2, 'Dhurandhars Revenge', 55, 3, 'Dhurandhars Revenge', 'league', 'League', 'Pratik Shah'),
    ('8DSJZt2W0YR2RcxWRN4t', '2026-06-27T13:45:00.000Z'::timestamptz, 'Jersey Indians', 38, 5, 'Short-Pitch Sharks', 29, 6, 'Jersey Indians', 'league', 'League', 'Swapnil Shah'),
    ('m8uHxgofJtB5nVNR1PgY', '2026-06-27T13:15:00.000Z'::timestamptz, 'Game Changers', 36, 5, 'Power Strikers', 38, 2, 'Power Strikers', 'league', 'League', 'Abhijeet Das'),
    ('oS93sbrssFyQQ1DZht4Q', '2026-06-27T12:45:00.000Z'::timestamptz, 'Jersey Warriors', 42, 4, 'Dhurandhars Revenge', 44, 2, 'Dhurandhars Revenge', 'league', 'League', 'Arup Dutta'),
    ('3RC8wS1vR9y4MBmYWC5u', '2026-06-27T12:15:00.000Z'::timestamptz, 'Shadow Strikers', 46, 5, 'Short-Pitch Sharks', 52, 5, 'Short-Pitch Sharks', 'league', 'League', 'Sundararajan Velayutham'),
    ('4Rf3TiIkd2BGO9nb84sJ', '2026-06-27T11:45:00.000Z'::timestamptz, 'Jersey Warriors', 54, 2, 'Game Changers', 41, 5, 'Jersey Warriors', 'league', 'League', 'Sanjay Solanki'),
    ('c7WgmrDhDNbhTxpuFaCO', '2026-06-13T14:45:00.000Z'::timestamptz, 'Power Strikers', 57, 2, 'Game Changers', 44, 3, 'Power Strikers', 'league', 'League', 'Dipesh Salkar'),
    ('uB67lpkIQka7TMTKMUxI', '2026-06-13T14:15:00.000Z'::timestamptz, 'Jersey Warriors', 40, 5, 'Jersey Indians', 43, 3, 'Jersey Indians', 'league', 'League', 'Sushant Gawali'),
    ('dHjZyXLYMwM74F3GdoaY', '2026-06-13T13:15:00.000Z'::timestamptz, 'Jersey Indians', 42, 2, 'Shadow Strikers', 44, 3, 'Shadow Strikers', 'league', 'League', 'Swapnil Shah'),
    ('GK4mJj0E02sY6onmEYw9', '2026-06-13T13:15:00.000Z'::timestamptz, 'Dhurandhars Revenge', 44, 2, 'Jersey Warriors', 43, 4, 'Dhurandhars Revenge', 'league', 'League', 'Pratik Shah'),
    ('qxvFgu6LvoOrQVxA5wrz', '2026-06-13T12:45:00.000Z'::timestamptz, 'Dhurandhars Revenge', 46, 5, 'Power Strikers', 53, 4, 'Power Strikers', 'league', 'League', 'Nikhil J'),
    ('bsTCVOJ8ppM5zKKWUgwV', '2026-06-13T12:15:00.000Z'::timestamptz, 'Game Changers', 24, 6, 'Short-Pitch Sharks', 28, 1, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('VJuRAJ6Ya8vS2jED9EcO', '2026-06-13T11:45:00.000Z'::timestamptz, 'Short-Pitch Sharks', 31, 2, 'Shadow Strikers', 27, 5, 'Short-Pitch Sharks', 'league', 'League', 'Supreeth Premkumar'),
    ('uEn5xiYRvc4serTseIRC', '2026-06-06T15:00:00.000Z'::timestamptz, 'Game Changers', 32, 4, 'Jersey Warriors', 41, 5, 'Jersey Warriors', 'league', 'League', 'Sanjay Solanki'),
    ('4mTPIbjraLNdTIkmScjr', '2026-06-06T14:30:00.000Z'::timestamptz, 'Dhurandhars Revenge', 36, 2, 'Jersey Indians', 38, 0, 'Jersey Indians', 'league', 'League', 'Mahesh Kshatriya'),
    ('U49N1E77Aa4MoncBdCiB', '2026-06-06T14:00:00.000Z'::timestamptz, 'Shadow Strikers', 43, 3, 'Game Changers', 43, 3, 'Game Changers', 'league', 'League', 'Sumit Lole'),
    ('cF7E8bDjtTgNdLvwJ33Y', '2026-06-06T13:30:00.000Z'::timestamptz, 'Jersey Warriors', 49, 2, 'Power Strikers', 33, 3, 'Jersey Warriors', 'league', 'League', 'Dipesh Salkar'),
    ('bvCepCfqXZ9OE7fw4pNh', '2026-06-06T13:00:00.000Z'::timestamptz, 'Short-Pitch Sharks', 37, 5, 'Jersey Indians', 51, 3, 'Jersey Indians', 'league', 'League', 'Swapnil Shah'),
    ('h45zxIbRYeMOZa9LUJgJ', '2026-06-06T12:30:00.000Z'::timestamptz, 'Dhurandhars Revenge', 31, 3, 'Shadow Strikers', 30, 6, 'Dhurandhars Revenge', 'league', 'League', 'Shreenath Kini'),
    ('kKMIJC3o3IC5NnjLYz11', '2026-06-06T12:00:00.000Z'::timestamptz, 'Short-Pitch Sharks', 48, 3, 'Power Strikers', 47, 3, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('vdFlPqFyfPokCLmrrVGN', '2026-05-30T14:30:00.000Z'::timestamptz, 'Shadow Strikers', 33, 6, 'Jersey Warriors', 55, 3, 'Jersey Warriors', 'league', 'League', 'Santosh Naidu'),
    ('QoaIQXg7DRv8sCTVnAHi', '2026-05-30T14:00:00.000Z'::timestamptz, 'Jersey Indians', 67, 2, 'Dhurandhars Revenge', 37, 2, 'Jersey Indians', 'league', 'League', 'Hari S'),
    ('JzZtwizNL9QQ00i1RJOC', '2026-05-30T13:30:00.000Z'::timestamptz, 'Power Strikers', 38, 5, 'Short-Pitch Sharks', 37, 1, 'Power Strikers', 'league', 'League', 'Mandar Patki'),
    ('LN8l0NbK1BvWyOAgemeG', '2026-05-30T13:00:00.000Z'::timestamptz, 'Shadow Strikers', 37, 4, 'Jersey Indians', 41, 4, 'Jersey Indians', 'league', 'League', 'Shreenath Kini'),
    ('8CB7VoAn5KehFctm4tUF', '2026-05-30T12:30:00.000Z'::timestamptz, 'Power Strikers', 35, 6, 'Jersey Warriors', 66, 1, 'Jersey Warriors', 'league', 'League', 'Santosh Naidu'),
    ('MIQfmVTeNAni3m6kU1mC', '2026-05-30T12:00:00.000Z'::timestamptz, 'Dhurandhars Revenge', 41, 3, 'Game Changers', 40, 4, 'Dhurandhars Revenge', 'league', 'League', 'Shubham Pandey'),
    ('LrDwu4w3oaSo7CitczUL', '2026-05-23T13:30:00.000Z'::timestamptz, 'Dhurandhars Revenge', 29, 4, 'Short-Pitch Sharks', 30, 4, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('xhySaIbo5X3mxzGr5jgk', '2026-05-23T13:00:00.000Z'::timestamptz, 'Jersey Indians', 53, 4, 'Jersey Warriors', 27, 5, 'Jersey Indians', 'league', 'League', 'Mahesh Kshatriya'),
    ('sRppuOO2stgvL1O65o23', '2026-05-23T12:30:00.000Z'::timestamptz, 'Short-Pitch Sharks', 52, 4, 'Game Changers', 52, 3, 'Short-Pitch Sharks', 'league', 'League', 'Hardik Shah'),
    ('AVIXE4hp3K73iuzIz60j', '2026-05-23T12:00:00.000Z'::timestamptz, 'Game Changers', 50, 3, 'Shadow Strikers', 31, 5, 'Game Changers', 'league', 'League', 'Manish Doijode'),
    ('A8ihPtKewPRzynSqqw2y', '2026-05-16T13:30:00.000Z'::timestamptz, 'Short-Pitch Sharks', 31, 6, 'Jersey Warriors', 34, 0, 'Jersey Warriors', 'league', 'League', 'Santosh Naidu'),
    ('BxK7ESO67PkhMm5iLZCE', '2026-05-16T13:00:00.000Z'::timestamptz, 'Shadow Strikers', 47, 2, 'Power Strikers', 45, 4, 'Shadow Strikers', 'league', 'League', 'Shreenath Kini'),
    ('RrM2s7jZcR9Dfbb6EcMJ', '2026-05-16T12:30:00.000Z'::timestamptz, 'Game Changers', 39, 4, 'Jersey Indians', 36, 3, 'Game Changers', 'league', 'League', 'Saravanan Veluchamy'),
    ('F1OYGnxSfyikgnjcS3q5', '2026-05-16T12:00:00.000Z'::timestamptz, 'Power Strikers', 38, 4, 'Dhurandhars Revenge', 40, 3, 'Dhurandhars Revenge', 'league', 'League', 'Pratik Shah')
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
  r.home_team_name,
  r.home_runs,
  r.home_wickets,
  away_st.id,
  r.away_team_name,
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
 and home_team.name = r.home_team_name
join public.season_teams home_st
  on home_st.season_id = sc.season_id
 and home_st.team_id = home_team.id
join public.teams away_team
  on away_team.league_id = sc.league_id
 and away_team.name = r.away_team_name
join public.season_teams away_st
  on away_st.season_id = sc.season_id
 and away_st.team_id = away_team.id
join public.teams winner_team
  on winner_team.league_id = sc.league_id
 and winner_team.name = r.winner_team_name
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

with source_rows (
  team_name, matches_played, wins, losses, draws, points,
  runs_for, balls_faced, runs_against, balls_bowled, net_run_rate
) as (
  values
    ('Jersey Indians', 14, 12, 2, 0, 24, 615, 454, 502, 502, 2.1277533039647585::numeric),
    ('Jersey Warriors', 14, 8, 6, 0, 16, 625, 491, 545, 487, 0.9228954863100487::numeric),
    ('Short-Pitch Sharks', 15, 8, 7, 0, 16, 571, 503, 588, 519, 0.013445339523553201::numeric),
    ('Dhurandhars Revenge', 13, 7, 6, 0, 14, 524, 446, 563, 445, -0.541683881694965::numeric),
    ('Power Strikers', 12, 5, 7, 0, 10, 499, 429, 537, 410, -0.8795156063448735::numeric),
    ('Game Changers', 12, 4, 8, 0, 8, 482, 432, 513, 403, -0.9432726771436455::numeric),
    ('Shadow Strikers', 12, 2, 10, 0, 4, 476, 426, 544, 415, -1.1608348888511806::numeric)
),
season_context as (
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
  r.matches_played,
  r.wins,
  r.losses,
  r.draws,
  r.points,
  r.runs_for,
  r.balls_faced,
  r.runs_against,
  r.balls_bowled,
  r.net_run_rate,
  '2026-07-25T17:47:15.359Z'::timestamptz
from source_rows r
join season_context sc on true
join public.teams t
  on t.league_id = sc.league_id
 and t.name = r.team_name
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

create or replace function public.get_public_season_standings(target_season_id uuid)
returns table (
  season_team_id uuid,
  team_id uuid,
  team_slug text,
  team_name text,
  matches_played bigint,
  wins bigint,
  losses bigint,
  draws bigint,
  points bigint,
  runs_for bigint,
  balls_faced bigint,
  runs_against bigint,
  balls_bowled bigint,
  net_run_rate numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with season_teams as (
    select
      st.id as season_team_id,
      t.id as team_id,
      t.slug as team_slug,
      t.name as team_name
    from public.season_teams st
    join public.teams t on t.id = st.team_id
    where st.season_id = target_season_id
  ),
  live_match_totals as (
    select
      ml.season_team_id,
      m.id as match_id,
      coalesce(
        (
          select mi.total_runs
          from public.match_innings mi
          where mi.match_id = m.id
            and mi.batting_season_team_id = ml.season_team_id
        ),
        sum(mps.runs)
      )::bigint as runs_for,
      sum(mps.balls_faced)::bigint as balls_faced,
      coalesce(
        (
          select mi.total_runs
          from public.match_innings mi
          where mi.match_id = m.id
            and mi.bowling_season_team_id = ml.season_team_id
        ),
        sum(mps.runs_conceded)
      )::bigint as runs_against,
      sum(mps.balls_bowled)::bigint as balls_bowled
    from public.matches m
    join public.match_lineups ml on ml.match_id = m.id
    join public.match_player_stats mps on mps.match_lineup_id = ml.id
    where m.season_id = target_season_id
      and m.status = 'completed'
    group by ml.season_team_id, m.id
  ),
  live_summary as (
    select
      cmt.season_team_id,
      count(*)::bigint as matches_played,
      count(*) filter (where m.winner_season_team_id = cmt.season_team_id)::bigint as wins,
      count(*) filter (where m.winner_season_team_id is not null and m.winner_season_team_id <> cmt.season_team_id)::bigint as losses,
      count(*) filter (where m.winner_season_team_id is null)::bigint as draws,
      coalesce(sum(cmt.runs_for), 0)::bigint as runs_for,
      coalesce(sum(cmt.balls_faced), 0)::bigint as balls_faced,
      coalesce(sum(cmt.runs_against), 0)::bigint as runs_against,
      coalesce(sum(cmt.balls_bowled), 0)::bigint as balls_bowled
    from live_match_totals cmt
    join public.matches m on m.id = cmt.match_id
    group by cmt.season_team_id
  ),
  live_with_nrr as (
    select
      ls.*,
      (ls.wins * 2 + ls.draws)::bigint as points,
      case
        when ls.balls_faced = 0 or ls.balls_bowled = 0 then 0::numeric
        else round(
          (
            (ls.runs_for::numeric / (ls.balls_faced::numeric / 6))
            - (ls.runs_against::numeric / (ls.balls_bowled::numeric / 6))
          ),
          3
        )
      end as net_run_rate
    from live_summary ls
  ),
  combined as (
    select
      st.season_team_id,
      st.team_id,
      st.team_slug,
      st.team_name,
      coalesce(legacy.matches_played, live.matches_played, 0)::bigint as matches_played,
      coalesce(legacy.wins, live.wins, 0)::bigint as wins,
      coalesce(legacy.losses, live.losses, 0)::bigint as losses,
      coalesce(legacy.draws, live.draws, 0)::bigint as draws,
      coalesce(legacy.points, live.points, 0)::bigint as points,
      coalesce(legacy.runs_for, live.runs_for, 0)::bigint as runs_for,
      coalesce(legacy.balls_faced, live.balls_faced, 0)::bigint as balls_faced,
      coalesce(legacy.runs_against, live.runs_against, 0)::bigint as runs_against,
      coalesce(legacy.balls_bowled, live.balls_bowled, 0)::bigint as balls_bowled,
      coalesce(legacy.net_run_rate, live.net_run_rate, 0::numeric) as net_run_rate
    from season_teams st
    left join public.legacy_season_standings legacy
      on legacy.season_id = target_season_id
     and legacy.season_team_id = st.season_team_id
    left join live_with_nrr live on live.season_team_id = st.season_team_id
  )
  select *
  from combined
  order by points desc, net_run_rate desc, wins desc, team_name asc;
$$;

grant execute on function public.get_public_season_standings(uuid) to anon, authenticated;

create or replace function public.get_public_matches_for_season(target_season_id uuid)
returns table (
  match_id uuid,
  season_id uuid,
  home_season_team_id uuid,
  home_team_name text,
  away_season_team_id uuid,
  away_team_name text,
  match_date timestamptz,
  venue text,
  status text,
  result_type text,
  winner_team_name text
)
language sql
stable
security definer
set search_path = public
as $$
  with public_matches as (
    select
      m.id as match_id,
      m.season_id,
      m.home_season_team_id,
      home_team.name as home_team_name,
      m.away_season_team_id,
      away_team.name as away_team_name,
      m.match_date,
      m.venue,
      m.status,
      m.result_type,
      winner_team.name as winner_team_name
    from public.matches m
    join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
    join public.teams home_team on home_team.id = home_season_team.team_id
    join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
    join public.teams away_team on away_team.id = away_season_team.team_id
    left join public.season_teams winner_season_team on winner_season_team.id = m.winner_season_team_id
    left join public.teams winner_team on winner_team.id = winner_season_team.team_id
    join public.seasons s on s.id = m.season_id
    where m.season_id = target_season_id
      and (
        m.status <> 'draft'
        or public.has_league_role(s.league_id, array['admin'])
      )
    union all
    select
      lmr.id,
      lmr.season_id,
      lmr.home_season_team_id,
      lmr.home_team_name,
      lmr.away_season_team_id,
      lmr.away_team_name,
      lmr.match_date,
      lmr.venue,
      'completed'::text,
      'win'::text,
      winner_team.name
    from public.legacy_match_results lmr
    join public.season_teams winner_season_team on winner_season_team.id = lmr.winner_season_team_id
    join public.teams winner_team on winner_team.id = winner_season_team.team_id
    where lmr.season_id = target_season_id
  )
  select *
  from public_matches
  order by match_date asc nulls last, home_team_name, away_team_name;
$$;

grant execute on function public.get_public_matches_for_season(uuid) to anon, authenticated;
