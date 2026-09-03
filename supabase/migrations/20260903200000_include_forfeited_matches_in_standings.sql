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
      and m.result_type <> 'forfeit'
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
  forfeit_summary as (
    select
      result.season_team_id,
      count(*)::bigint as matches_played,
      count(*) filter (where m.winner_season_team_id = result.season_team_id)::bigint as wins,
      count(*) filter (where m.winner_season_team_id <> result.season_team_id)::bigint as losses,
      0::bigint as draws
    from public.matches m
    cross join lateral (
      values (m.home_season_team_id), (m.away_season_team_id)
    ) as result(season_team_id)
    where m.season_id = target_season_id
      and m.status = 'completed'
      and m.result_type = 'forfeit'
    group by result.season_team_id
  ),
  live_with_nrr as (
    select
      coalesce(ls.season_team_id, fs.season_team_id) as season_team_id,
      coalesce(ls.matches_played, 0) + coalesce(fs.matches_played, 0) as matches_played,
      coalesce(ls.wins, 0) + coalesce(fs.wins, 0) as wins,
      coalesce(ls.losses, 0) + coalesce(fs.losses, 0) as losses,
      coalesce(ls.draws, 0) + coalesce(fs.draws, 0) as draws,
      coalesce(ls.runs_for, 0)::bigint as runs_for,
      coalesce(ls.balls_faced, 0)::bigint as balls_faced,
      coalesce(ls.runs_against, 0)::bigint as runs_against,
      coalesce(ls.balls_bowled, 0)::bigint as balls_bowled,
      case
        when coalesce(ls.balls_faced, 0) = 0 or coalesce(ls.balls_bowled, 0) = 0 then 0::numeric
        else round(
          (
            (ls.runs_for::numeric / (ls.balls_faced::numeric / 6))
            - (ls.runs_against::numeric / (ls.balls_bowled::numeric / 6))
          ),
          3
        )
      end as net_run_rate
    from live_summary ls
    full outer join forfeit_summary fs on fs.season_team_id = ls.season_team_id
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
      coalesce(legacy.points, (coalesce(live.wins, 0) * 2 + coalesce(live.draws, 0)), 0)::bigint as points,
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
