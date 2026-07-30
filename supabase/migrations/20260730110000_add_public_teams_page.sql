create or replace function public.get_public_league_seasons(target_league_slug text default 'box-cricket-league')
returns table (
  league_id uuid,
  league_name text,
  season_id uuid,
  season_name text,
  starts_on date,
  ends_on date,
  is_current boolean
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
      s.starts_on,
      s.ends_on,
      row_number() over (
        partition by l.id
        order by s.starts_on desc nulls last, s.created_at desc, s.name desc
      ) = 1 as is_current
    from public.leagues l
    join public.seasons s on s.league_id = l.id
    where l.slug = target_league_slug
  )
  select
    league_id,
    league_name,
    season_id,
    season_name,
    starts_on,
    ends_on,
    is_current
  from league_seasons
  order by is_current desc, starts_on desc nulls last, season_name desc;
$$;

create or replace function public.get_public_teams_for_season(target_season_id uuid)
returns table (
  season_team_id uuid,
  team_id uuid,
  team_slug text,
  team_name text,
  manager_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    st.id as season_team_id,
    t.id as team_id,
    t.slug as team_slug,
    t.name as team_name,
    nullif(
      string_agg(
        coalesce(nullif(btrim(stm.display_name), ''), p.display_name),
        ', '
        order by coalesce(nullif(btrim(stm.display_name), ''), p.display_name)
      ),
      ''
    ) as manager_name
  from public.season_teams st
  join public.teams t on t.id = st.team_id
  left join public.season_team_managers stm on stm.season_team_id = st.id
  left join public.players p on p.id = stm.player_id
  where st.season_id = target_season_id
  group by st.id, t.id, t.slug, t.name
  order by t.name;
$$;

grant execute on function public.get_public_league_seasons(text) to anon, authenticated;
grant execute on function public.get_public_teams_for_season(uuid) to anon, authenticated;
