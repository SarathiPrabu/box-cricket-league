-- Correct the second-innings batsman for the completed August 1 Jersey match.
-- The score, delivery events, and bowling assignments remain unchanged.

create temporary table jersey_match_batsman_correction on commit drop as
select
  md.id as delivery_id,
  mi.id as innings_id,
  mbt.id as batting_turn_id,
  'c029d381-4506-4d27-a65d-73951f1b9f78'::uuid as sumit_season_roster_id,
  'a65a161e-ed69-48e5-bd1a-3703f992172f'::uuid as sonu_season_roster_id
from public.match_deliveries md
join public.match_innings mi on mi.id = md.innings_id
join public.match_batting_turns mbt on mbt.id = md.batting_turn_id
join public.match_over_assignments moa on moa.id = md.over_assignment_id
where mi.match_id = 'af679945-0786-4b63-ac74-4e8e32256ada'::uuid
  and mi.innings_number = 2
  and mbt.id = 'c56e0614-81ce-4bb0-9745-ac00182e8356'::uuid
  and md.striker_season_roster_id = 'a65a161e-ed69-48e5-bd1a-3703f992172f'::uuid
  and (
    (moa.over_number = 5 and md.legal_ball_number in (5, 6))
    or (moa.over_number = 6 and md.legal_ball_number in (1, 2))
  );

do $migration$
begin
  if (select count(*) from jersey_match_batsman_correction) not in (0, 4) then
    raise exception 'Jersey match batsman correction expected four target deliveries';
  end if;
end;
$migration$;

-- Completed overs and inactive batting turns are intentionally immutable in
-- normal scoring. Bypass only those two guards for this controlled correction.
alter table public.match_deliveries
  disable trigger match_deliveries_prevent_confirmed_over_change;
alter table public.match_deliveries
  disable trigger match_deliveries_validate;

update public.match_batting_turns mbt
set batter_season_roster_id = correction.sumit_season_roster_id,
    updated_at = now()
from (
  select distinct batting_turn_id, sumit_season_roster_id
  from jersey_match_batsman_correction
) correction
where mbt.id = correction.batting_turn_id;

update public.match_deliveries md
set striker_season_roster_id = correction.sumit_season_roster_id,
    updated_at = now()
from jersey_match_batsman_correction correction
where md.id = correction.delivery_id;

alter table public.match_deliveries
  enable trigger match_deliveries_validate;
alter table public.match_deliveries
  enable trigger match_deliveries_prevent_confirmed_over_change;

-- Rebuild the two affected finalized player rows from delivery source data.
with recalculated as (
  select
    ml.id as match_lineup_id,
    coalesce(sum(case when md.striker_season_roster_id = ml.season_roster_id then md.batter_runs else 0 end), 0)::integer as runs,
    count(*) filter (where md.striker_season_roster_id = ml.season_roster_id and md.delivery_type = 'legal')::integer as balls_faced,
    count(*) filter (where md.striker_season_roster_id = ml.season_roster_id and md.batter_runs = 4)::integer as fours,
    count(*) filter (where md.striker_season_roster_id = ml.season_roster_id and md.batter_runs = 6)::integer as sixes,
    count(*) filter (where md.bowler_season_roster_id = ml.season_roster_id and md.delivery_type = 'legal')::integer as balls_bowled,
    coalesce(sum(case when md.bowler_season_roster_id = ml.season_roster_id then md.batter_runs + md.extra_runs else 0 end), 0)::integer as runs_conceded,
    count(*) filter (
      where md.bowler_season_roster_id = ml.season_roster_id
        and md.is_wicket
        and md.dismissal_type in ('bowled', 'caught', 'stumped', 'hit_wicket', 'hit_out_of_field')
    )::integer as wickets,
    count(*) filter (where md.fielder_season_roster_id = ml.season_roster_id and md.dismissal_type = 'caught')::integer as catches,
    count(*) filter (where md.fielder_season_roster_id = ml.season_roster_id and md.dismissal_type = 'stumped')::integer as stumpings
  from public.match_lineups ml
  left join public.match_deliveries md
    on md.innings_id in (
      select mi.id
      from public.match_innings mi
      where mi.match_id = 'af679945-0786-4b63-ac74-4e8e32256ada'::uuid
    )
  where ml.match_id = 'af679945-0786-4b63-ac74-4e8e32256ada'::uuid
    and ml.season_roster_id in (
      'c029d381-4506-4d27-a65d-73951f1b9f78'::uuid,
      'a65a161e-ed69-48e5-bd1a-3703f992172f'::uuid
    )
  group by ml.id, ml.season_roster_id
)
update public.match_player_stats stats
set runs = recalculated.runs,
    balls_faced = recalculated.balls_faced,
    fours = recalculated.fours,
    sixes = recalculated.sixes,
    balls_bowled = recalculated.balls_bowled,
    runs_conceded = recalculated.runs_conceded,
    wickets = recalculated.wickets,
    catches = recalculated.catches,
    stumpings = recalculated.stumpings,
    updated_at = now()
from recalculated
where stats.match_lineup_id = recalculated.match_lineup_id;
