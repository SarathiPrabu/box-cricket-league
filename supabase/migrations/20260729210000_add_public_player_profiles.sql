create or replace function public.slugify_player_name(value text)
returns text
language sql
immutable
strict
set search_path = public
as $$
  select trim(both '-' from regexp_replace(lower(value), '[^a-z0-9]+', '-', 'g'));
$$;

alter table public.players
  add column slug text;

with ranked_players as (
  select
    id,
    public.slugify_player_name(display_name) as base_slug,
    row_number() over (
      partition by public.slugify_player_name(display_name)
      order by id
    ) as slug_number
  from public.players
)
update public.players p
set slug = case
  when rp.slug_number = 1 then rp.base_slug
  else rp.base_slug || '-' || rp.slug_number
end
from ranked_players rp
where p.id = rp.id;

alter table public.players
  alter column slug set not null,
  add constraint players_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  add constraint players_slug_unique unique (slug);

create or replace function public.set_player_slug()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  base_slug text;
begin
  if new.slug is null then
    base_slug := coalesce(nullif(public.slugify_player_name(new.display_name), ''), 'player');
    new.slug := base_slug;

    if exists (select 1 from public.players p where p.slug = base_slug) then
      new.slug := base_slug || '-' || left(replace(new.id::text, '-', ''), 8);
    end if;
  end if;

  return new;
end;
$$;

create trigger players_set_slug
before insert on public.players
for each row execute function public.set_player_slug();

create or replace function public.get_public_player_by_slug(player_slug text)
returns table (
  id uuid,
  display_name text,
  full_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.full_name
  from public.players p
  where p.slug = player_slug;
$$;

create or replace function public.get_public_player_season_stats(target_player_id uuid)
returns table (
  season_id uuid,
  season_name text,
  starts_on date,
  team_name text,
  matches_played bigint,
  runs bigint,
  balls_faced bigint,
  fours bigint,
  sixes bigint,
  balls_bowled bigint,
  runs_conceded bigint,
  wickets bigint,
  catches bigint,
  stumpings bigint,
  player_of_match_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with raw_stats as (
    select
      m.season_id,
      sr.player_id,
      count(distinct m.id)::bigint as matches_played,
      sum(mps.runs)::bigint as runs,
      sum(mps.balls_faced)::bigint as balls_faced,
      sum(mps.fours)::bigint as fours,
      sum(mps.sixes)::bigint as sixes,
      sum(mps.balls_bowled)::bigint as balls_bowled,
      sum(mps.runs_conceded)::bigint as runs_conceded,
      sum(mps.wickets)::bigint as wickets,
      sum(mps.catches)::bigint as catches,
      sum(mps.stumpings)::bigint as stumpings,
      count(*) filter (where mps.is_player_of_match)::bigint as player_of_match_count
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    join public.matches m on m.id = ml.match_id and m.status = 'completed'
    join public.season_rosters sr on sr.id = ml.season_roster_id
    where sr.player_id = target_player_id
    group by m.season_id, sr.player_id
  ), season_stats as (
    select * from raw_stats
    union all
    select
      lsps.season_id,
      lsps.player_id,
      lsps.matches_played::bigint,
      lsps.runs::bigint,
      lsps.balls_faced::bigint,
      lsps.fours::bigint,
      lsps.sixes::bigint,
      lsps.balls_bowled::bigint,
      lsps.runs_conceded::bigint,
      lsps.wickets::bigint,
      lsps.catches::bigint,
      lsps.stumpings::bigint,
      lsps.player_of_match_count::bigint
    from public.legacy_season_player_stats lsps
    where lsps.player_id = target_player_id
      and not exists (
        select 1
        from raw_stats rs
        where rs.season_id = lsps.season_id
          and rs.player_id = lsps.player_id
      )
  )
  select
    s.id,
    s.name,
    s.starts_on,
    t.name,
    coalesce(ss.matches_played, 0),
    coalesce(ss.runs, 0),
    coalesce(ss.balls_faced, 0),
    coalesce(ss.fours, 0),
    coalesce(ss.sixes, 0),
    coalesce(ss.balls_bowled, 0),
    coalesce(ss.runs_conceded, 0),
    coalesce(ss.wickets, 0),
    coalesce(ss.catches, 0),
    coalesce(ss.stumpings, 0),
    coalesce(ss.player_of_match_count, 0)
  from public.season_rosters sr
  join public.seasons s on s.id = sr.season_id
  join public.season_teams st on st.id = sr.season_team_id
  join public.teams t on t.id = st.team_id
  left join season_stats ss
    on ss.season_id = sr.season_id
    and ss.player_id = sr.player_id
  where sr.player_id = target_player_id
  order by s.starts_on nulls first, s.created_at, s.name;
$$;

grant execute on function public.get_public_player_by_slug(text) to anon, authenticated;
grant execute on function public.get_public_player_season_stats(uuid) to anon, authenticated;
