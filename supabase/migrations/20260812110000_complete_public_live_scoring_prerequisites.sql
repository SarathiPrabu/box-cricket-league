-- Complete the two scorer prerequisites that were skipped remotely.
--
-- The original non-striker migration cannot be applied after batting turns because
-- it would restore the older delivery-validation function. Keep this correction
-- focused on the required column/constraint changes and temporary public access.

alter table public.match_deliveries
  alter column non_striker_season_roster_id drop not null;

alter table public.match_deliveries
  drop constraint if exists match_deliveries_players_distinct,
  add constraint match_deliveries_players_distinct check (
    non_striker_season_roster_id is null
    or striker_season_roster_id <> non_striker_season_roster_id
  ),
  drop constraint if exists match_deliveries_no_ball_batter_runs_check,
  add constraint match_deliveries_no_ball_batter_runs_check check (
    delivery_type <> 'no_ball'
    or batter_runs in (0, 1, 2, 4, 6)
  );

-- Temporary review mode. These security-definer scoring functions already have
-- no role guard in the deployed live-scoring migration, so only access grants
-- and read policies are required here.
grant execute on function public.start_match(uuid, uuid) to anon, authenticated;
grant execute on function public.select_match_batter(uuid, uuid) to anon, authenticated;
grant execute on function public.set_match_over_assignment(uuid, integer, uuid, uuid) to anon, authenticated;
grant execute on function public.record_match_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.update_current_over_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.delete_current_over_delivery(uuid) to anon, authenticated;
grant execute on function public.complete_match_innings(uuid) to anon, authenticated;
grant execute on function public.finalize_match(uuid, uuid) to anon, authenticated;
grant execute on function public.mark_match_no_result(uuid) to anon, authenticated;
grant execute on function public.get_match_scoring_state(uuid) to anon, authenticated;

grant select on public.matches,
  public.match_innings,
  public.match_over_assignments,
  public.match_deliveries,
  public.match_batting_turns
to anon, authenticated;

drop policy if exists "public can read matches for live scoring" on public.matches;
create policy "public can read matches for live scoring"
on public.matches
for select
using (true);

drop policy if exists "public can read match innings for live scoring" on public.match_innings;
create policy "public can read match innings for live scoring"
on public.match_innings
for select
using (true);

drop policy if exists "public can read match overs for live scoring" on public.match_over_assignments;
create policy "public can read match overs for live scoring"
on public.match_over_assignments
for select
using (true);

drop policy if exists "public can read match deliveries for live scoring" on public.match_deliveries;
create policy "public can read match deliveries for live scoring"
on public.match_deliveries
for select
using (true);

drop policy if exists "public can read batting turns for live scoring" on public.match_batting_turns;
create policy "public can read batting turns for live scoring"
on public.match_batting_turns
for select
using (true);
