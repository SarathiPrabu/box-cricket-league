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
  completed_match_totals as (
    select
      ml.season_team_id,
      m.id as match_id,
      sum(mps.runs)::bigint as runs_for,
      sum(mps.balls_faced)::bigint as balls_faced,
      sum(mps.runs_conceded)::bigint as runs_against,
      sum(mps.balls_bowled)::bigint as balls_bowled
    from public.matches m
    join public.match_lineups ml on ml.match_id = m.id
    join public.match_player_stats mps on mps.match_lineup_id = ml.id
    where m.season_id = target_season_id
      and m.status = 'completed'
    group by ml.season_team_id, m.id
  ),
  season_summary as (
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
    from completed_match_totals cmt
    join public.matches m on m.id = cmt.match_id
    group by cmt.season_team_id
  )
  select
    st.season_team_id,
    st.team_id,
    st.team_slug,
    st.team_name,
    coalesce(ss.matches_played, 0) as matches_played,
    coalesce(ss.wins, 0) as wins,
    coalesce(ss.losses, 0) as losses,
    coalesce(ss.draws, 0) as draws,
    (coalesce(ss.wins, 0) * 2 + coalesce(ss.draws, 0))::bigint as points,
    coalesce(ss.runs_for, 0) as runs_for,
    coalesce(ss.balls_faced, 0) as balls_faced,
    coalesce(ss.runs_against, 0) as runs_against,
    coalesce(ss.balls_bowled, 0) as balls_bowled,
    case
      when coalesce(ss.balls_faced, 0) = 0 or coalesce(ss.balls_bowled, 0) = 0 then 0::numeric
      else round(
        (
          (coalesce(ss.runs_for, 0)::numeric / (coalesce(ss.balls_faced, 0)::numeric / 6))
          - (coalesce(ss.runs_against, 0)::numeric / (coalesce(ss.balls_bowled, 0)::numeric / 6))
        ),
        3
      )
    end as net_run_rate
  from season_teams st
  left join season_summary ss on ss.season_team_id = st.season_team_id
  order by points desc, net_run_rate desc, wins desc, team_name asc;
$$;

grant execute on function public.get_public_season_standings(uuid) to anon, authenticated;
