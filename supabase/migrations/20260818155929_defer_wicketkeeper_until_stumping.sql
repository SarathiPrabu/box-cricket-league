-- Over setup stores a provisional keeper because the existing scoring state
-- expects a roster id, but the keeper only matters when a stumping is recorded.
alter table public.match_over_assignments
  drop constraint if exists match_over_assignments_bowler_keeper_distinct;

-- Preserve the actual cricket rule at the point where it matters: a stumping
-- must credit a real wicketkeeper who is not bowling the delivery.
alter table public.match_deliveries
  drop constraint if exists match_deliveries_stumping_keeper_bowler_distinct,
  add constraint match_deliveries_stumping_keeper_bowler_distinct check (
    dismissal_type is distinct from 'stumped'
    or (
      fielder_season_roster_id is not null
      and fielder_season_roster_id <> bowler_season_roster_id
    )
  ) not valid;

alter table public.match_deliveries
  validate constraint match_deliveries_stumping_keeper_bowler_distinct;
