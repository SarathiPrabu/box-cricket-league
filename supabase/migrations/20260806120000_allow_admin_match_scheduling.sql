grant select, insert, update, delete on public.matches to authenticated;

create or replace function public.validate_match()
returns trigger
language plpgsql
security definer
set search_path = public
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
