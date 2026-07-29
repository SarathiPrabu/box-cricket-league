create table public.legacy_season_player_stats (
  id uuid primary key default extensions.gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  player_id uuid not null references public.players(id) on delete restrict,
  season_roster_id uuid references public.season_rosters(id) on delete restrict,
  source text not null,
  source_player_id text not null,
  source_team_name text not null,
  matches_played integer not null,
  runs integer not null,
  balls_faced integer not null,
  fours integer not null,
  sixes integer not null,
  balls_bowled integer not null,
  runs_conceded integer not null,
  wickets integer not null,
  catches integer not null,
  stumpings integer not null,
  player_of_match_count integer not null,
  total_points integer not null,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legacy_season_player_stats_source_unique unique (season_id, source, source_player_id),
  constraint legacy_season_player_stats_non_negative check (
    matches_played >= 0
    and runs >= 0
    and balls_faced >= 0
    and fours >= 0
    and sixes >= 0
    and balls_bowled >= 0
    and runs_conceded >= 0
    and wickets >= 0
    and catches >= 0
    and stumpings >= 0
    and player_of_match_count >= 0
    and total_points >= 0
  )
);

create index legacy_season_player_stats_season_id_idx
  on public.legacy_season_player_stats (season_id);

create index legacy_season_player_stats_player_id_idx
  on public.legacy_season_player_stats (player_id);

create index legacy_season_player_stats_season_roster_id_idx
  on public.legacy_season_player_stats (season_roster_id);

create trigger legacy_season_player_stats_set_updated_at
before update on public.legacy_season_player_stats
for each row execute function public.set_updated_at();

alter table public.legacy_season_player_stats enable row level security;

create policy "league members can read legacy season player stats"
on public.legacy_season_player_stats
for select
using (
  exists (
    select 1
    from public.seasons s
    where s.id = legacy_season_player_stats.season_id
      and public.is_league_member(s.league_id)
  )
);

create policy "league admins can manage legacy season player stats"
on public.legacy_season_player_stats
for all
using (
  exists (
    select 1
    from public.seasons s
    where s.id = legacy_season_player_stats.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
)
with check (
  exists (
    select 1
    from public.seasons s
    where s.id = legacy_season_player_stats.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
);
