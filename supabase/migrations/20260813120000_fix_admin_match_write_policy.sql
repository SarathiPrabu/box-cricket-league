-- Replace any earlier match-write policy with the helper-based check.
-- Direct reads from seasons fail for browser roles because the table remains protected by RLS.
drop policy if exists "league admins can manage matches" on public.matches;

create policy "league admins can manage matches"
on public.matches
for all
using (
  public.has_league_role(
    public.league_id_for_match(id),
    array['admin']
  )
)
with check (
  public.has_league_role(
    public.league_id_for_season(season_id),
    array['admin']
  )
);
