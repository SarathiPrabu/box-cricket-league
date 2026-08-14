-- Keep individual batter runs separate from the final team score. Team totals
-- include extras and are persisted on each completed innings for standings.
alter table public.match_innings
  add column if not exists total_runs integer not null default 0;

alter table public.match_innings
  drop constraint if exists match_innings_total_runs_non_negative,
  add constraint match_innings_total_runs_non_negative check (total_runs >= 0);

-- Backfill completed innings from the delivery source of truth. This repairs
-- existing matches without assigning team extras to an individual batter.
update public.match_innings mi
set total_runs = coalesce((
      select sum(md.batter_runs + md.extra_runs)::integer
      from public.match_deliveries md
      where md.innings_id = mi.id
    ), 0),
    updated_at = now()
where exists (
  select 1
  from public.matches m
  where m.id = mi.match_id
    and m.status = 'completed'
);

-- Persist the final team total whenever an innings is completed. The deployed
-- function may include later access-control or scoring fixes, so replace only
-- the stable update fragment instead of redefining the whole function here.
do $migration$
declare
  function_definition text;
  old_fragment constant text := $fragment$
  update public.match_innings
  set status = 'completed',
      completed_at = now(),
      updated_at = now()
  where id = target_innings_id;
$fragment$;
  new_fragment constant text := $fragment$
  update public.match_innings
  set status = 'completed',
      total_runs = innings_score,
      completed_at = now(),
      updated_at = now()
  where id = target_innings_id;
$fragment$;
begin
  select pg_get_functiondef('public.complete_match_innings(uuid)'::regprocedure)
  into function_definition;

  if position('total_runs = innings_score' in function_definition) > 0 then
    return;
  end if;

  if position(old_fragment in function_definition) = 0 then
    raise exception 'complete_match_innings score update could not be updated safely';
  end if;

  execute replace(function_definition, old_fragment, new_fragment);
end;
$migration$;

-- Persist both final team totals during finalization as a second integrity
-- shield for matches whose innings were completed before this migration.
do $migration$
declare
  function_definition text;
  old_fragment constant text := $fragment$
  insert into public.match_player_stats (
$fragment$;
  new_fragment constant text := $fragment$
  update public.match_innings
  set total_runs = case innings_number
        when 1 then first_score
        when 2 then second_score
      end,
      updated_at = now()
  where match_id = target_match_id;

  insert into public.match_player_stats (
$fragment$;
begin
  select pg_get_functiondef('public.finalize_match(uuid,uuid)'::regprocedure)
  into function_definition;

  if position('set total_runs = case innings_number' in function_definition) > 0 then
    return;
  end if;

  if position(old_fragment in function_definition) = 0 then
    raise exception 'finalize_match team total update could not be updated safely';
  end if;

  execute replace(function_definition, old_fragment, new_fragment);
end;
$migration$;

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
