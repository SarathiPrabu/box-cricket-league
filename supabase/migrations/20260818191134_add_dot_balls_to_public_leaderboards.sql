drop function if exists public.get_public_season_leaderboards(uuid);

create function public.get_public_season_leaderboards(target_season_id uuid)
returns table (player_id uuid, player_slug text, player_name text, team_name text, matches_played bigint, runs bigint, balls_faced bigint, fours bigint, sixes bigint, balls_bowled bigint, dot_balls_bowled bigint, runs_conceded bigint, wickets bigint, catches bigint, stumpings bigint, player_of_match_count bigint)
language sql stable security definer set search_path = public
as $$
  with raw_stats as (
    select m.season_id, sr.player_id, null::text as source_team_name,
      count(distinct m.id)::bigint as matches_played, coalesce(sum(mps.runs), 0)::bigint as runs,
      coalesce(sum(mps.balls_faced), 0)::bigint as balls_faced, coalesce(sum(mps.fours), 0)::bigint as fours,
      coalesce(sum(mps.sixes), 0)::bigint as sixes, coalesce(sum(mps.balls_bowled), 0)::bigint as balls_bowled,
      coalesce(dot_stats.dot_balls_bowled, 0)::bigint as dot_balls_bowled, coalesce(sum(mps.runs_conceded), 0)::bigint as runs_conceded,
      coalesce(sum(mps.wickets), 0)::bigint as wickets, coalesce(sum(mps.catches), 0)::bigint as catches,
      coalesce(sum(mps.stumpings), 0)::bigint as stumpings, count(*) filter (where mps.is_player_of_match)::bigint as player_of_match_count
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    join public.matches m on m.id = ml.match_id and m.status = 'completed'
    join public.season_rosters sr on sr.id = ml.season_roster_id
    left join (
      select m_dot.season_id, bowler_roster.player_id, count(*)::bigint as dot_balls_bowled
      from public.match_deliveries md
      join public.match_innings mi on mi.id = md.innings_id
      join public.matches m_dot on m_dot.id = mi.match_id and m_dot.status = 'completed'
      join public.season_rosters bowler_roster on bowler_roster.id = md.bowler_season_roster_id
      where md.delivery_type = 'legal' and md.batter_runs + md.extra_runs = 0
      group by m_dot.season_id, bowler_roster.player_id
    ) dot_stats on dot_stats.season_id = m.season_id and dot_stats.player_id = sr.player_id
    where m.season_id = target_season_id
    group by m.season_id, sr.player_id, dot_stats.dot_balls_bowled
  ), legacy_stats as (
    select lsps.season_id, lsps.player_id, lsps.source_team_name, lsps.matches_played::bigint, lsps.runs::bigint,
      lsps.balls_faced::bigint, lsps.fours::bigint, lsps.sixes::bigint, lsps.balls_bowled::bigint, 0::bigint as dot_balls_bowled,
      lsps.runs_conceded::bigint, lsps.wickets::bigint, lsps.catches::bigint, lsps.stumpings::bigint, lsps.player_of_match_count::bigint
    from public.legacy_season_player_stats lsps where lsps.season_id = target_season_id
      and not exists (select 1 from raw_stats rs where rs.season_id = lsps.season_id and rs.player_id = lsps.player_id)
  ), season_stats as (select * from raw_stats union all select * from legacy_stats)
  select p.id, p.slug, p.display_name, coalesce(t.name, ss.source_team_name), ss.matches_played, ss.runs, ss.balls_faced,
    ss.fours, ss.sixes, ss.balls_bowled, ss.dot_balls_bowled, ss.runs_conceded, ss.wickets, ss.catches, ss.stumpings, ss.player_of_match_count
  from season_stats ss join public.players p on p.id = ss.player_id
  left join public.season_rosters sr on sr.season_id = ss.season_id and sr.player_id = ss.player_id
  left join public.season_teams st on st.id = sr.season_team_id left join public.teams t on t.id = st.team_id
  where ss.season_id = target_season_id order by p.display_name asc;
$$;

grant execute on function public.get_public_season_leaderboards(uuid) to anon, authenticated;
