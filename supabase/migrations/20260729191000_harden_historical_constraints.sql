-- Keep historical league data from being accidentally erased by parent deletes.
alter table public.teams
  drop constraint if exists teams_league_id_fkey,
  add constraint teams_league_id_fkey
    foreign key (league_id) references public.leagues(id) on delete restrict;

alter table public.seasons
  drop constraint if exists seasons_league_id_fkey,
  add constraint seasons_league_id_fkey
    foreign key (league_id) references public.leagues(id) on delete restrict;

alter table public.season_teams
  drop constraint if exists season_teams_season_id_fkey,
  drop constraint if exists season_teams_team_id_fkey,
  add constraint season_teams_season_id_fkey
    foreign key (season_id) references public.seasons(id) on delete restrict,
  add constraint season_teams_team_id_fkey
    foreign key (team_id) references public.teams(id) on delete restrict;

alter table public.season_team_managers
  drop constraint if exists season_team_managers_season_team_id_fkey,
  add constraint season_team_managers_season_team_id_fkey
    foreign key (season_team_id) references public.season_teams(id) on delete restrict;

alter table public.season_rosters
  drop constraint if exists season_rosters_season_team_id_fkey,
  drop constraint if exists season_rosters_season_id_fkey,
  add constraint season_rosters_season_team_id_fkey
    foreign key (season_team_id) references public.season_teams(id) on delete restrict,
  add constraint season_rosters_season_id_fkey
    foreign key (season_id) references public.seasons(id) on delete restrict;

alter table public.matches
  drop constraint if exists matches_season_id_fkey,
  add constraint matches_season_id_fkey
    foreign key (season_id) references public.seasons(id) on delete restrict;

alter table public.match_staff
  drop constraint if exists match_staff_match_id_fkey,
  add constraint match_staff_match_id_fkey
    foreign key (match_id) references public.matches(id) on delete restrict;

alter table public.match_lineups
  drop constraint if exists match_lineups_match_id_fkey,
  add constraint match_lineups_match_id_fkey
    foreign key (match_id) references public.matches(id) on delete restrict;

alter table public.match_player_stats
  drop constraint if exists match_player_stats_match_lineup_id_fkey,
  add constraint match_player_stats_match_lineup_id_fkey
    foreign key (match_lineup_id) references public.match_lineups(id) on delete restrict;

create or replace function public.validate_match()
returns trigger
language plpgsql
as $$
declare
  home_season_id uuid;
  away_season_id uuid;
  winner_season_id uuid;
  home_lineup_count integer;
  away_lineup_count integer;
  home_captain_count integer;
  away_captain_count integer;
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
    select
      count(*) filter (where ml.season_team_id = new.home_season_team_id),
      count(*) filter (where ml.season_team_id = new.away_season_team_id),
      count(*) filter (where ml.season_team_id = new.home_season_team_id and ml.is_captain),
      count(*) filter (where ml.season_team_id = new.away_season_team_id and ml.is_captain)
    into
      home_lineup_count,
      away_lineup_count,
      home_captain_count,
      away_captain_count
    from public.match_lineups ml
    where ml.match_id = new.id;

    if home_lineup_count < 1 or away_lineup_count < 1 then
      raise exception 'completed match must have at least one lineup player for each team';
    end if;

    if home_captain_count <> 1 or away_captain_count <> 1 then
      raise exception 'completed match must have exactly one captain for each team';
    end if;

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

drop trigger if exists match_player_stats_validate_completed_match_player_of_match
on public.match_player_stats;

drop function if exists public.validate_completed_match_player_of_match();

create or replace function public.set_player_of_match(target_match_player_stats_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  target_match_id uuid;
begin
  select ml.match_id into target_match_id
  from public.match_player_stats mps
  join public.match_lineups ml on ml.id = mps.match_lineup_id
  where mps.id = target_match_player_stats_id;

  if target_match_id is null then
    raise exception 'match player stats row not found';
  end if;

  update public.match_player_stats mps
  set is_player_of_match = false
  from public.match_lineups ml
  where ml.id = mps.match_lineup_id
    and ml.match_id = target_match_id
    and mps.is_player_of_match;

  update public.match_player_stats
  set is_player_of_match = true
  where id = target_match_player_stats_id;
end;
$$;
