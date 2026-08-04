create or replace function public.slugify_season_name(value text)
returns text
language sql
immutable
strict
set search_path = public
as $$
select trim(both '-' from regexp_replace(lower(value), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function public.get_public_team_for_season(
  target_team_slug text,
  target_season_slug text default null,
  target_league_slug text default 'box-cricket-league'
)
returns table (
  league_id uuid,
  league_name text,
  season_id uuid,
  season_name text,
  players_per_team integer,
  is_current boolean,
  season_team_id uuid,
  team_id uuid,
  team_slug text,
  team_name text,
  manager_name text,
  roster_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with league_seasons as (
    select
      l.id as league_id,
      l.name as league_name,
      s.id as season_id,
      s.name as season_name,
      s.players_per_team,
      row_number() over (
        partition by l.id
        order by s.starts_on desc nulls last, s.created_at desc, s.name desc
      ) = 1 as is_current
    from public.leagues l
    join public.seasons s on s.league_id = l.id
    where l.slug = target_league_slug
  )
select
    ls.league_id,
    ls.league_name,
    ls.season_id,
    ls.season_name,
    ls.players_per_team,
    ls.is_current,
    st.id as season_team_id,
    t.id as team_id,
    t.slug as team_slug,
    t.name as team_name,
    nullif(
            string_agg(
                distinct coalesce(nullif(btrim(stm.display_name), ''), mp.display_name),
                    ', '
            ),
            ''
    ) as manager_name,
    count(distinct sr.id)::bigint as roster_count
from league_seasons ls
         join public.season_teams st on st.season_id = ls.season_id
         join public.teams t on t.id = st.team_id and t.slug = target_team_slug
         left join public.season_team_managers stm on stm.season_team_id = st.id
         left join public.players mp on mp.id = stm.player_id
         left join public.season_rosters sr on sr.season_team_id = st.id
where target_season_slug is null
   or public.slugify_season_name(ls.season_name) = target_season_slug
group by
    ls.league_id,
    ls.league_name,
    ls.season_id,
    ls.season_name,
    ls.players_per_team,
    ls.is_current,
    st.id,
    t.id,
    t.slug,
    t.name
order by
    case when target_season_slug is null and ls.is_current then 0 else 1 end,
    ls.season_name desc
    limit 1;
$$;

create or replace function public.get_public_team_roster(target_season_team_id uuid)
returns table (
  season_roster_id uuid,
  player_id uuid,
  player_slug text,
  display_name text,
  full_name text,
  is_manager boolean
)
language sql
stable
security definer
set search_path = public
as $$
select
    sr.id as season_roster_id,
    p.id as player_id,
    p.slug as player_slug,
    p.display_name,
    p.full_name,
    exists (
        select 1
        from public.season_team_managers stm
        where stm.season_team_id = sr.season_team_id
          and stm.player_id = sr.player_id
    ) as is_manager
from public.season_rosters sr
         join public.players p on p.id = sr.player_id
where sr.season_team_id = target_season_team_id
order by is_manager desc, p.display_name;
$$;

grant execute on function public.slugify_season_name(text) to anon, authenticated;
grant execute on function public.get_public_team_for_season(text, text, text) to anon, authenticated;
grant execute on function public.get_public_team_roster(uuid) to anon, authenticated;
