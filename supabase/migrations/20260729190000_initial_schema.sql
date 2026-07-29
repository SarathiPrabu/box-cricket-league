create extension if not exists pgcrypto with schema extensions;

create table public.leagues (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null,
  slug text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leagues_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint leagues_slug_unique unique (slug)
);

create table public.league_members (
  id uuid primary key default extensions.gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  constraint league_members_role_check check (role in ('admin', 'moderator')),
  constraint league_members_league_user_unique unique (league_id, user_id)
);

create table public.players (
  id uuid primary key default extensions.gen_random_uuid(),
  display_name text not null,
  full_name text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teams (
  id uuid primary key default extensions.gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  name text not null,
  slug text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teams_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint teams_league_slug_unique unique (league_id, slug)
);

create table public.seasons (
  id uuid primary key default extensions.gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  name text not null,
  starts_on date,
  ends_on date,
  players_per_team integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint seasons_players_per_team_positive check (players_per_team > 0),
  constraint seasons_dates_order check (ends_on is null or starts_on is null or ends_on >= starts_on),
  constraint seasons_league_name_unique unique (league_id, name)
);

create table public.season_teams (
  id uuid primary key default extensions.gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint season_teams_season_team_unique unique (season_id, team_id)
);

create table public.season_team_managers (
  id uuid primary key default extensions.gen_random_uuid(),
  season_team_id uuid not null references public.season_teams(id) on delete cascade,
  player_id uuid references public.players(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  display_name text,
  created_at timestamptz not null default now(),
  constraint season_team_managers_identity_check check (
    player_id is not null
    or user_id is not null
    or nullif(btrim(display_name), '') is not null
  )
);

create table public.season_rosters (
  id uuid primary key default extensions.gen_random_uuid(),
  season_team_id uuid not null references public.season_teams(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint season_rosters_season_team_player_unique unique (season_team_id, player_id),
  constraint season_rosters_season_player_unique unique (season_id, player_id)
);

create table public.matches (
  id uuid primary key default extensions.gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  home_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  away_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  match_date timestamptz,
  venue text,
  status text not null default 'scheduled',
  youtube_url text,
  winner_season_team_id uuid references public.season_teams(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint matches_status_check check (status in ('scheduled', 'completed', 'cancelled')),
  constraint matches_distinct_teams check (home_season_team_id <> away_season_team_id)
);

create table public.match_staff (
  id uuid primary key default extensions.gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  role text not null,
  season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint match_staff_role_check check (role in ('umpire', 'commentator')),
  constraint match_staff_match_role_roster_unique unique (match_id, role, season_roster_id)
);

create table public.match_lineups (
  id uuid primary key default extensions.gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  season_team_id uuid not null references public.season_teams(id) on delete restrict,
  season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  is_captain boolean not null default false,
  selected_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_lineups_match_roster_unique unique (match_id, season_roster_id)
);

create unique index match_lineups_one_captain_per_team
  on public.match_lineups (match_id, season_team_id)
  where is_captain;

create table public.match_player_stats (
  id uuid primary key default extensions.gen_random_uuid(),
  match_lineup_id uuid not null references public.match_lineups(id) on delete cascade,
  runs integer not null default 0,
  balls_faced integer not null default 0,
  fours integer not null default 0,
  sixes integer not null default 0,
  balls_bowled integer not null default 0,
  runs_conceded integer not null default 0,
  wickets integer not null default 0,
  catches integer not null default 0,
  stumpings integer not null default 0,
  is_player_of_match boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_player_stats_lineup_unique unique (match_lineup_id),
  constraint match_player_stats_non_negative check (
    runs >= 0
    and balls_faced >= 0
    and fours >= 0
    and sixes >= 0
    and balls_bowled >= 0
    and runs_conceded >= 0
    and wickets >= 0
    and catches >= 0
    and stumpings >= 0
  )
);

create index league_members_user_id_idx on public.league_members (user_id);
create index teams_league_id_idx on public.teams (league_id);
create index seasons_league_id_idx on public.seasons (league_id);
create index season_teams_season_id_idx on public.season_teams (season_id);
create index season_teams_team_id_idx on public.season_teams (team_id);
create index season_team_managers_season_team_id_idx on public.season_team_managers (season_team_id);
create index season_team_managers_player_id_idx on public.season_team_managers (player_id);
create index season_rosters_season_team_id_idx on public.season_rosters (season_team_id);
create index season_rosters_season_id_idx on public.season_rosters (season_id);
create index season_rosters_player_id_idx on public.season_rosters (player_id);
create index matches_season_id_idx on public.matches (season_id);
create index match_staff_match_id_idx on public.match_staff (match_id);
create index match_staff_season_roster_id_idx on public.match_staff (season_roster_id);
create index match_lineups_match_id_idx on public.match_lineups (match_id);
create index match_lineups_season_team_id_idx on public.match_lineups (season_team_id);
create index match_lineups_season_roster_id_idx on public.match_lineups (season_roster_id);
create index match_player_stats_match_lineup_id_idx on public.match_player_stats (match_lineup_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger leagues_set_updated_at
before update on public.leagues
for each row execute function public.set_updated_at();

create trigger players_set_updated_at
before update on public.players
for each row execute function public.set_updated_at();

create trigger teams_set_updated_at
before update on public.teams
for each row execute function public.set_updated_at();

create trigger seasons_set_updated_at
before update on public.seasons
for each row execute function public.set_updated_at();

create trigger matches_set_updated_at
before update on public.matches
for each row execute function public.set_updated_at();

create trigger match_lineups_set_updated_at
before update on public.match_lineups
for each row execute function public.set_updated_at();

create trigger match_player_stats_set_updated_at
before update on public.match_player_stats
for each row execute function public.set_updated_at();

create or replace function public.validate_season_team()
returns trigger
language plpgsql
as $$
declare
  season_league_id uuid;
  team_league_id uuid;
begin
  select league_id into season_league_id
  from public.seasons
  where id = new.season_id;

  select league_id into team_league_id
  from public.teams
  where id = new.team_id;

  if season_league_id is distinct from team_league_id then
    raise exception 'season team must use a team from the same league as the season';
  end if;

  return new;
end;
$$;

create trigger season_teams_validate
before insert or update on public.season_teams
for each row execute function public.validate_season_team();

create or replace function public.validate_season_roster()
returns trigger
language plpgsql
as $$
declare
  roster_season_id uuid;
begin
  select season_id into roster_season_id
  from public.season_teams
  where id = new.season_team_id;

  if roster_season_id is distinct from new.season_id then
    raise exception 'season roster season_id must match the selected season team';
  end if;

  return new;
end;
$$;

create trigger season_rosters_validate
before insert or update on public.season_rosters
for each row execute function public.validate_season_roster();

create or replace function public.validate_match()
returns trigger
language plpgsql
as $$
declare
  home_season_id uuid;
  away_season_id uuid;
  winner_season_id uuid;
  player_of_match_count integer;
begin
  select season_id into home_season_id
  from public.season_teams
  where id = new.home_season_team_id;

  select season_id into away_season_id
  from public.season_teams
  where id = new.away_season_team_id;

  if home_season_id is distinct from new.season_id then
    raise exception 'home team must belong to the match season';
  end if;

  if away_season_id is distinct from new.season_id then
    raise exception 'away team must belong to the match season';
  end if;

  if new.winner_season_team_id is not null then
    if new.winner_season_team_id not in (new.home_season_team_id, new.away_season_team_id) then
      raise exception 'winner must be one of the match teams';
    end if;

    select season_id into winner_season_id
    from public.season_teams
    where id = new.winner_season_team_id;

    if winner_season_id is distinct from new.season_id then
      raise exception 'winner must belong to the match season';
    end if;
  end if;

  if new.status = 'completed' then
    select count(*) into player_of_match_count
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    where ml.match_id = new.id
      and mps.is_player_of_match;

    if player_of_match_count <> 1 then
      raise exception 'completed match must have exactly one player of the match';
    end if;
  end if;

  return new;
end;
$$;

create trigger matches_validate
before insert or update on public.matches
for each row execute function public.validate_match();

create or replace function public.validate_match_staff()
returns trigger
language plpgsql
as $$
declare
  match_season_id uuid;
  roster_season_id uuid;
begin
  select season_id into match_season_id
  from public.matches
  where id = new.match_id;

  select season_id into roster_season_id
  from public.season_rosters
  where id = new.season_roster_id;

  if roster_season_id is distinct from match_season_id then
    raise exception 'match staff must belong to the same season as the match';
  end if;

  if exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = new.match_id
      and ml.season_roster_id = new.season_roster_id
  ) then
    raise exception 'match staff cannot also be in the playing lineup';
  end if;

  return new;
end;
$$;

create trigger match_staff_validate
before insert or update on public.match_staff
for each row execute function public.validate_match_staff();

create or replace function public.validate_match_lineup()
returns trigger
language plpgsql
as $$
declare
  match_record public.matches%rowtype;
  roster_season_team_id uuid;
begin
  select * into match_record
  from public.matches
  where id = new.match_id;

  if new.season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id) then
    raise exception 'lineup team must be one of the match teams';
  end if;

  select season_team_id into roster_season_team_id
  from public.season_rosters
  where id = new.season_roster_id;

  if roster_season_team_id is distinct from new.season_team_id then
    raise exception 'lineup roster must belong to the lineup team';
  end if;

  if exists (
    select 1
    from public.match_staff ms
    where ms.match_id = new.match_id
      and ms.season_roster_id = new.season_roster_id
  ) then
    raise exception 'match official cannot also be in the playing lineup';
  end if;

  return new;
end;
$$;

create trigger match_lineups_validate
before insert or update on public.match_lineups
for each row execute function public.validate_match_lineup();

create or replace function public.validate_player_of_match()
returns trigger
language plpgsql
as $$
declare
  target_match_id uuid;
begin
  if not new.is_player_of_match then
    return new;
  end if;

  select match_id into target_match_id
  from public.match_lineups
  where id = new.match_lineup_id;

  if exists (
    select 1
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    where ml.match_id = target_match_id
      and mps.is_player_of_match
      and mps.id <> new.id
  ) then
    raise exception 'only one player of the match is allowed per match';
  end if;

  return new;
end;
$$;

create trigger match_player_stats_validate_player_of_match
before insert or update on public.match_player_stats
for each row execute function public.validate_player_of_match();

create or replace function public.validate_completed_match_player_of_match()
returns trigger
language plpgsql
as $$
declare
  target_match_id uuid;
  target_match_status text;
  player_of_match_count integer;
begin
  select match_id into target_match_id
  from public.match_lineups
  where id = coalesce(new.match_lineup_id, old.match_lineup_id);

  select status into target_match_status
  from public.matches
  where id = target_match_id;

  if target_match_status = 'completed' then
    select count(*) into player_of_match_count
    from public.match_player_stats mps
    join public.match_lineups ml on ml.id = mps.match_lineup_id
    where ml.match_id = target_match_id
      and mps.is_player_of_match;

    if player_of_match_count <> 1 then
      raise exception 'completed match must have exactly one player of the match';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger match_player_stats_validate_completed_match_player_of_match
after insert or update or delete on public.match_player_stats
for each row execute function public.validate_completed_match_player_of_match();

create or replace function public.is_league_member(target_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.league_members lm
    where lm.league_id = target_league_id
      and lm.user_id = auth.uid()
  );
$$;

create or replace function public.has_league_role(target_league_id uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.league_members lm
    where lm.league_id = target_league_id
      and lm.user_id = auth.uid()
      and lm.role = any(allowed_roles)
  );
$$;

create or replace function public.league_id_for_season_team(target_season_team_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.league_id
  from public.season_teams st
  join public.seasons s on s.id = st.season_id
  where st.id = target_season_team_id;
$$;

create or replace function public.league_id_for_match(target_match_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.league_id
  from public.matches m
  join public.seasons s on s.id = m.season_id
  where m.id = target_match_id;
$$;

create or replace function public.league_id_for_match_lineup(target_match_lineup_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select public.league_id_for_match(ml.match_id)
  from public.match_lineups ml
  where ml.id = target_match_lineup_id;
$$;

alter table public.leagues enable row level security;
alter table public.league_members enable row level security;
alter table public.players enable row level security;
alter table public.teams enable row level security;
alter table public.seasons enable row level security;
alter table public.season_teams enable row level security;
alter table public.season_team_managers enable row level security;
alter table public.season_rosters enable row level security;
alter table public.matches enable row level security;
alter table public.match_staff enable row level security;
alter table public.match_lineups enable row level security;
alter table public.match_player_stats enable row level security;

create policy "league members can read leagues"
on public.leagues
for select
using (public.is_league_member(id));

create policy "league admins can update leagues"
on public.leagues
for update
using (public.has_league_role(id, array['admin']))
with check (public.has_league_role(id, array['admin']));

create policy "league members can read league members"
on public.league_members
for select
using (public.is_league_member(league_id));

create policy "league admins can manage league members"
on public.league_members
for all
using (public.has_league_role(league_id, array['admin']))
with check (public.has_league_role(league_id, array['admin']));

create policy "league members can read rostered players"
on public.players
for select
using (
  created_by = auth.uid()
  or exists (
    select 1
    from public.season_rosters sr
    join public.seasons s on s.id = sr.season_id
    where sr.player_id = players.id
      and public.is_league_member(s.league_id)
  )
);

create policy "authenticated users can create players"
on public.players
for insert
with check (auth.uid() is not null);

create policy "player creators or league admins can update players"
on public.players
for update
using (
  created_by = auth.uid()
  or exists (
    select 1
    from public.season_rosters sr
    join public.seasons s on s.id = sr.season_id
    where sr.player_id = players.id
      and public.has_league_role(s.league_id, array['admin'])
  )
)
with check (
  created_by = auth.uid()
  or exists (
    select 1
    from public.season_rosters sr
    join public.seasons s on s.id = sr.season_id
    where sr.player_id = players.id
      and public.has_league_role(s.league_id, array['admin'])
  )
);

create policy "league members can read teams"
on public.teams
for select
using (public.is_league_member(league_id));

create policy "league admins can manage teams"
on public.teams
for all
using (public.has_league_role(league_id, array['admin']))
with check (public.has_league_role(league_id, array['admin']));

create policy "league members can read seasons"
on public.seasons
for select
using (public.is_league_member(league_id));

create policy "league admins can manage seasons"
on public.seasons
for all
using (public.has_league_role(league_id, array['admin']))
with check (public.has_league_role(league_id, array['admin']));

create policy "league members can read season teams"
on public.season_teams
for select
using (public.is_league_member(public.league_id_for_season_team(id)));

create policy "league admins can manage season teams"
on public.season_teams
for all
using (public.has_league_role(public.league_id_for_season_team(id), array['admin']))
with check (
  exists (
    select 1
    from public.seasons s
    where s.id = season_teams.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
);

create policy "league members can read season team managers"
on public.season_team_managers
for select
using (public.is_league_member(public.league_id_for_season_team(season_team_id)));

create policy "league admins can manage season team managers"
on public.season_team_managers
for all
using (public.has_league_role(public.league_id_for_season_team(season_team_id), array['admin']))
with check (public.has_league_role(public.league_id_for_season_team(season_team_id), array['admin']));

create policy "league members can read season rosters"
on public.season_rosters
for select
using (
  exists (
    select 1
    from public.seasons s
    where s.id = season_rosters.season_id
      and public.is_league_member(s.league_id)
  )
);

create policy "league admins can manage season rosters"
on public.season_rosters
for all
using (
  exists (
    select 1
    from public.seasons s
    where s.id = season_rosters.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
)
with check (
  exists (
    select 1
    from public.seasons s
    where s.id = season_rosters.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
);

create policy "league members can read matches"
on public.matches
for select
using (public.is_league_member(public.league_id_for_match(id)));

create policy "league admins can manage matches"
on public.matches
for all
using (public.has_league_role(public.league_id_for_match(id), array['admin']))
with check (
  exists (
    select 1
    from public.seasons s
    where s.id = matches.season_id
      and public.has_league_role(s.league_id, array['admin'])
  )
);

create policy "league members can read match staff"
on public.match_staff
for select
using (public.is_league_member(public.league_id_for_match(match_id)));

create policy "league admins can manage match staff"
on public.match_staff
for all
using (public.has_league_role(public.league_id_for_match(match_id), array['admin']))
with check (public.has_league_role(public.league_id_for_match(match_id), array['admin']));

create policy "league members can read match lineups"
on public.match_lineups
for select
using (public.is_league_member(public.league_id_for_match(match_id)));

create policy "league admins can manage match lineups"
on public.match_lineups
for all
using (public.has_league_role(public.league_id_for_match(match_id), array['admin']))
with check (public.has_league_role(public.league_id_for_match(match_id), array['admin']));

create policy "league members can read match player stats"
on public.match_player_stats
for select
using (public.is_league_member(public.league_id_for_match_lineup(match_lineup_id)));

create policy "league admins can manage match player stats"
on public.match_player_stats
for all
using (public.has_league_role(public.league_id_for_match_lineup(match_lineup_id), array['admin']))
with check (public.has_league_role(public.league_id_for_match_lineup(match_lineup_id), array['admin']));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.matches,
      public.match_lineups,
      public.match_player_stats;
  end if;
end;
$$;
