create or replace function public.league_id_for_season(target_season_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.league_id
  from public.seasons s
  where s.id = target_season_id;
$$;

grant execute on function public.league_id_for_season(uuid) to authenticated;

drop policy if exists "league admins can manage matches" on public.matches;

create policy "league admins can manage matches"
on public.matches
for all
using (public.has_league_role(public.league_id_for_match(id), array['admin']))
with check (
  public.has_league_role(
    public.league_id_for_season(season_id),
    array['admin']
  )
);
