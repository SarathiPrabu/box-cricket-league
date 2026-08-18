-- Dead balls add one extra by default in the scorer, but corrected deliveries
-- may contain any non-negative batter and extra runs allowed by the base table.
-- Remove only the obsolete Dead ball validation fragments so later scoring and
-- authorization changes in the deployed functions remain intact.
do $migration$
declare
  function_definition text;
  old_fragment constant text := $fragment$
  if new.delivery_type = 'dead_ball' and (new.batter_runs <> 0 or new.extra_runs <> 0 or new.is_wicket) then
    raise exception 'dead balls cannot score runs or wickets';
  end if;

$fragment$;
begin
  select pg_get_functiondef('public.validate_match_delivery()'::regprocedure)
  into function_definition;

  if position('dead balls cannot score runs or wickets' in function_definition) > 0 then
    if position(old_fragment in function_definition) = 0 then
      raise exception 'validate_match_delivery Dead ball rule could not be removed safely';
    end if;

    execute replace(function_definition, old_fragment, '');
  end if;
end;
$migration$;

do $migration$
declare
  function_definition text;
  old_fragment constant text := $fragment$
  if target_delivery_type = 'dead_ball'
    and (target_batter_runs <> 0 or target_extra_runs <> 0 or target_is_wicket) then
    raise exception 'dead balls cannot score runs or wickets';
  end if;

$fragment$;
begin
  select pg_get_functiondef(
    'public.record_match_delivery(uuid,uuid,uuid,text,integer,integer,boolean,uuid,text,uuid)'::regprocedure
  ) into function_definition;

  if position('dead balls cannot score runs or wickets' in function_definition) > 0 then
    if position(old_fragment in function_definition) = 0 then
      raise exception 'record_match_delivery Dead ball rule could not be removed safely';
    end if;

    execute replace(function_definition, old_fragment, '');
  end if;
end;
$migration$;

-- Capture only historical Dead balls that still have the obsolete zero-extra
-- value. The table makes the score repair and any required match reopening
-- deterministic and idempotent.
create temporary table affected_dead_ball_deliveries on commit drop as
select
  md.id as delivery_id,
  md.innings_id,
  mi.match_id,
  mi.innings_number,
  md.bowler_season_roster_id
from public.match_deliveries md
join public.match_innings mi on mi.id = md.innings_id
where md.delivery_type = 'dead_ball'
  and md.extra_runs = 0;

-- Completed overs and inactive batting turns are intentionally immutable in
-- normal scoring. Bypass only those two guards for this controlled backfill.
alter table public.match_deliveries
  disable trigger match_deliveries_prevent_confirmed_over_change;
alter table public.match_deliveries
  disable trigger match_deliveries_validate;

update public.match_deliveries md
set extra_runs = 1,
    updated_at = now()
where md.id in (
  select affected.delivery_id
  from affected_dead_ball_deliveries affected
);

alter table public.match_deliveries
  enable trigger match_deliveries_validate;
alter table public.match_deliveries
  enable trigger match_deliveries_prevent_confirmed_over_change;

-- Recalculate the persisted team totals from the delivery source of truth.
update public.match_innings mi
set total_runs = totals.total_runs,
    updated_at = now()
from (
  select
    affected.innings_id,
    coalesce(sum(md.batter_runs + md.extra_runs), 0)::integer as total_runs
  from (
    select distinct innings_id
    from affected_dead_ball_deliveries
  ) affected
  left join public.match_deliveries md on md.innings_id = affected.innings_id
  group by affected.innings_id
) totals
where mi.id = totals.innings_id;

-- A chase that ended only because the old zero-extra first-innings score was
-- reached must resume when the corrected scores are level and legal balls
-- remain. Capture it before updating the target from the corrected first score.
create temporary table matches_to_reopen on commit drop as
select
  m.id as match_id,
  second_innings.id as second_innings_id
from public.matches m
join public.match_innings first_innings
  on first_innings.match_id = m.id
 and first_innings.innings_number = 1
join public.match_innings second_innings
  on second_innings.match_id = m.id
 and second_innings.innings_number = 2
where m.status = 'completed'
  and m.result_type = 'win'
  and first_innings.status = 'completed'
  and second_innings.status = 'completed'
  and first_innings.total_runs = second_innings.total_runs
  and second_innings.target_score = second_innings.total_runs
  and (
    select count(*)
    from public.match_deliveries md
    where md.innings_id = second_innings.id
      and md.delivery_type = 'legal'
  ) < second_innings.legal_balls_limit
  and exists (
    select 1
    from affected_dead_ball_deliveries affected
    where affected.match_id = m.id
      and affected.innings_number = 1
  );

-- Any second-innings target derived from an affected first innings must also
-- reflect the corrected team score, including matches whose result is unchanged.
update public.match_innings second_innings
set target_score = first_innings.total_runs + 1,
    updated_at = now()
from public.match_innings first_innings
where second_innings.match_id = first_innings.match_id
  and second_innings.innings_number = 2
  and first_innings.innings_number = 1
  and exists (
    select 1
    from affected_dead_ball_deliveries affected
    where affected.innings_id = first_innings.id
  );

-- Preserve finalized bowling statistics for completed matches whose result did
-- not change. Reopened matches have all derived stats removed below.
with bowler_additions as (
  select
    affected.match_id,
    affected.bowler_season_roster_id,
    count(*)::integer as additional_runs
  from affected_dead_ball_deliveries affected
  join public.matches m on m.id = affected.match_id
  left join matches_to_reopen reopening on reopening.match_id = affected.match_id
  where m.status = 'completed'
    and reopening.match_id is null
  group by affected.match_id, affected.bowler_season_roster_id
)
update public.match_player_stats stats
set runs_conceded = stats.runs_conceded + additions.additional_runs,
    updated_at = now()
from public.match_lineups lineup,
     bowler_additions additions
where stats.match_lineup_id = lineup.id
  and lineup.match_id = additions.match_id
  and lineup.season_roster_id = additions.bowler_season_roster_id;

-- Clear the invalid result before deleting derived stats. The scorer can then
-- continue the second innings from its existing partial over and batting turn.
update public.matches m
set status = 'live',
    result_type = null,
    winner_season_team_id = null,
    updated_at = now()
from matches_to_reopen reopening
where m.id = reopening.match_id;

delete from public.match_player_stats stats
using public.match_lineups lineup,
      matches_to_reopen reopening
where stats.match_lineup_id = lineup.id
  and lineup.match_id = reopening.match_id;

update public.match_innings innings
set status = 'live',
    completed_at = null,
    updated_at = now()
from matches_to_reopen reopening
where innings.id = reopening.second_innings_id;

-- complete_match_innings ends the active batting turn. Restore the unfinished
-- turn so the same batter can face the remaining ball of the partial over.
update public.match_batting_turns batting_turn
set status = 'active',
    end_reason = null,
    ended_at = null,
    updated_at = now()
where batting_turn.id in (
  select candidate.id
  from matches_to_reopen reopening
  cross join lateral (
    select mbt.id
    from public.match_batting_turns mbt
    where mbt.innings_id = reopening.second_innings_id
      and mbt.end_reason = 'innings_end'
      and not exists (
        select 1
        from public.match_deliveries wicket_delivery
        where wicket_delivery.batting_turn_id = mbt.id
          and wicket_delivery.is_wicket
      )
      and (
        select count(*)
        from public.match_deliveries turn_delivery
        where turn_delivery.batting_turn_id = mbt.id
          and turn_delivery.delivery_type = 'legal'
      ) < 6
    order by mbt.turn_number desc
    limit 1
  ) candidate
);

alter table public.match_over_assignments
  disable trigger match_over_assignments_validate_lock;

update public.match_over_assignments over_assignment
set confirmed_at = null,
    updated_at = now()
where over_assignment.id in (
  select candidate.id
  from matches_to_reopen reopening
  cross join lateral (
    select moa.id
    from public.match_over_assignments moa
    join public.match_innings mi on mi.id = moa.innings_id
    where moa.innings_id = reopening.second_innings_id
      and (
        select count(*)
        from public.match_deliveries md
        where md.over_assignment_id = moa.id
          and md.delivery_type = 'legal'
      ) < mi.balls_per_over
    order by moa.over_number desc
    limit 1
  ) candidate
);

alter table public.match_over_assignments
  enable trigger match_over_assignments_validate_lock;
