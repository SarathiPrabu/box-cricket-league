alter table public.seasons
  add column if not exists match_min_players integer not null default 5,
  add column if not exists match_max_players integer not null default 6,
  add column if not exists balls_per_over integer not null default 6,
  add column if not exists max_overs_per_player integer not null default 1;

alter table public.seasons
  drop constraint if exists seasons_match_player_count_check,
  add constraint seasons_match_player_count_check check (
    match_min_players >= 1
    and match_max_players >= match_min_players
  ),
  drop constraint if exists seasons_balls_per_over_check,
  add constraint seasons_balls_per_over_check check (balls_per_over > 0),
  drop constraint if exists seasons_max_overs_per_player_check,
  add constraint seasons_max_overs_per_player_check check (max_overs_per_player > 0);

alter table public.matches
  add column if not exists result_type text;

alter table public.matches
  drop constraint if exists matches_status_check,
  add constraint matches_status_check
    check (status in ('draft', 'scheduled', 'live', 'completed', 'cancelled')),
  drop constraint if exists matches_result_type_check,
  add constraint matches_result_type_check
    check (result_type is null or result_type in ('win', 'tie', 'no_result'));

create table public.match_innings (
  id uuid primary key default extensions.gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  innings_number smallint not null,
  batting_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  bowling_season_team_id uuid not null references public.season_teams(id) on delete restrict,
  overs_limit integer not null,
  balls_per_over integer not null,
  legal_balls_limit integer not null,
  max_overs_per_player integer not null default 1,
  target_score integer,
  status text not null default 'live',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_innings_number_check check (innings_number in (1, 2)),
  constraint match_innings_teams_distinct check (batting_season_team_id <> bowling_season_team_id),
  constraint match_innings_limits_check check (
    overs_limit > 0
    and balls_per_over > 0
    and legal_balls_limit = overs_limit * balls_per_over
    and max_overs_per_player > 0
    and (target_score is null or target_score >= 1)
  ),
  constraint match_innings_status_check check (status in ('live', 'completed')),
  constraint match_innings_match_number_unique unique (match_id, innings_number)
);

create table public.match_over_assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  innings_id uuid not null references public.match_innings(id) on delete cascade,
  over_number integer not null,
  batting_slot_season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  bowler_season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  wicketkeeper_season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_over_assignments_over_number_check check (over_number > 0),
  constraint match_over_assignments_bowler_keeper_distinct check (
    bowler_season_roster_id <> wicketkeeper_season_roster_id
  ),
  constraint match_over_assignments_innings_over_unique unique (innings_id, over_number)
);

create table public.match_deliveries (
  id uuid primary key default extensions.gen_random_uuid(),
  innings_id uuid not null references public.match_innings(id) on delete cascade,
  over_assignment_id uuid not null references public.match_over_assignments(id) on delete cascade,
  delivery_sequence integer not null,
  legal_ball_number integer,
  striker_season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  non_striker_season_roster_id uuid references public.season_rosters(id) on delete restrict,
  bowler_season_roster_id uuid not null references public.season_rosters(id) on delete restrict,
  delivery_type text not null,
  batter_runs integer not null default 0,
  extra_runs integer not null default 0,
  is_wicket boolean not null default false,
  dismissed_season_roster_id uuid references public.season_rosters(id) on delete restrict,
  dismissal_type text,
  fielder_season_roster_id uuid references public.season_rosters(id) on delete restrict,
  recorded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_deliveries_sequence_check check (delivery_sequence > 0),
  constraint match_deliveries_legal_ball_check check (
    legal_ball_number is null or legal_ball_number between 1 and 6
  ),
  constraint match_deliveries_players_distinct check (
    non_striker_season_roster_id is null
    or striker_season_roster_id <> non_striker_season_roster_id
  ),
  constraint match_deliveries_type_check check (
    delivery_type in ('legal', 'wide', 'no_ball', 'dead_ball')
  ),
  constraint match_deliveries_runs_check check (
    batter_runs >= 0
    and extra_runs >= 0
  ),
  constraint match_deliveries_wicket_type_check check (
    (not is_wicket and dismissed_season_roster_id is null and dismissal_type is null and fielder_season_roster_id is null)
    or (is_wicket and dismissed_season_roster_id is not null and dismissal_type is not null)
  ),
  constraint match_deliveries_dismissal_type_check check (
    dismissal_type is null
    or dismissal_type in ('bowled', 'caught', 'stumped', 'run_out', 'hit_wicket')
  ),
  constraint match_deliveries_sequence_unique unique (innings_id, delivery_sequence)
);

create unique index match_deliveries_over_legal_ball_unique
  on public.match_deliveries (over_assignment_id, legal_ball_number)
  where legal_ball_number is not null;

create index match_innings_match_id_idx on public.match_innings (match_id);
create index match_over_assignments_innings_id_idx on public.match_over_assignments (innings_id);
create index match_deliveries_innings_id_idx on public.match_deliveries (innings_id);
create index match_deliveries_over_assignment_id_idx on public.match_deliveries (over_assignment_id);
create index match_deliveries_striker_id_idx on public.match_deliveries (striker_season_roster_id);
create index match_deliveries_bowler_id_idx on public.match_deliveries (bowler_season_roster_id);

create trigger match_innings_set_updated_at
before update on public.match_innings
for each row execute function public.set_updated_at();

create trigger match_over_assignments_set_updated_at
before update on public.match_over_assignments
for each row execute function public.set_updated_at();

create trigger match_deliveries_set_updated_at
before update on public.match_deliveries
for each row execute function public.set_updated_at();

create or replace function public.league_id_for_innings(target_innings_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select public.league_id_for_match(mi.match_id)
  from public.match_innings mi
  where mi.id = target_innings_id;
$$;

create or replace function public.league_id_for_over_assignment(target_over_assignment_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select public.league_id_for_innings(moa.innings_id)
  from public.match_over_assignments moa
  where moa.id = target_over_assignment_id;
$$;

create or replace function public.league_id_for_delivery(target_delivery_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select public.league_id_for_innings(md.innings_id)
  from public.match_deliveries md
  where md.id = target_delivery_id;
$$;

grant execute on function public.league_id_for_innings(uuid) to authenticated;
grant execute on function public.league_id_for_over_assignment(uuid) to authenticated;
grant execute on function public.league_id_for_delivery(uuid) to authenticated;

alter table public.match_innings enable row level security;
alter table public.match_over_assignments enable row level security;
alter table public.match_deliveries enable row level security;

grant select on public.match_innings, public.match_over_assignments, public.match_deliveries to authenticated;

create policy "league members can read match innings"
on public.match_innings
for select
using (public.is_league_member(public.league_id_for_innings(id)));

create policy "league members can read match over assignments"
on public.match_over_assignments
for select
using (public.is_league_member(public.league_id_for_over_assignment(id)));

create policy "league members can read match deliveries"
on public.match_deliveries
for select
using (public.is_league_member(public.league_id_for_delivery(id)));

grant select on public.matches, public.match_innings, public.match_over_assignments, public.match_deliveries to anon;

create policy "public can read matches for live scoring"
on public.matches
for select
using (true);

create policy "public can read match innings for live scoring"
on public.match_innings
for select
using (true);

create policy "public can read match overs for live scoring"
on public.match_over_assignments
for select
using (true);

create policy "public can read match deliveries for live scoring"
on public.match_deliveries
for select
using (true);

drop policy if exists "league admins and scorers can manage matches" on public.matches;
drop policy if exists "league admins can manage matches" on public.matches;

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

drop policy if exists "league admins and scorers can manage match player stats" on public.match_player_stats;
drop policy if exists "league admins can manage match player stats" on public.match_player_stats;

create policy "league admins can manage match player stats"
on public.match_player_stats
for all
using (public.has_league_role(public.league_id_for_match_lineup(match_lineup_id), array['admin']))
with check (public.has_league_role(public.league_id_for_match_lineup(match_lineup_id), array['admin']));

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

  if new.result_type = 'win' and new.winner_season_team_id is null then
    raise exception 'a win must have a winner';
  end if;

  if new.result_type in ('tie', 'no_result') and new.winner_season_team_id is not null then
    raise exception 'a tie or no result cannot have a winner';
  end if;

  if new.status = 'completed' then
    if new.result_type is null then
      raise exception 'completed match must have a result type';
    end if;

    if new.result_type <> 'no_result' then
      select count(*)::integer into player_of_match_count
      from public.match_player_stats mps
      join public.match_lineups ml on ml.id = mps.match_lineup_id
      where ml.match_id = new.id
        and mps.is_player_of_match;

      if player_of_match_count <> 1 then
        raise exception 'completed match must have exactly one player of the match';
      end if;
    end if;
  elsif new.result_type is not null or new.winner_season_team_id is not null then
    raise exception 'result data is only allowed on completed matches';
  end if;

  return new;
end;
$$;

create or replace function public.validate_completed_match_player_of_match()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_match_id uuid;
  target_match_status text;
  target_result_type text;
  player_of_match_count integer;
begin
  select match_id into target_match_id
  from public.match_lineups
  where id = coalesce(new.match_lineup_id, old.match_lineup_id);

  select status, result_type
  into target_match_status, target_result_type
  from public.matches
  where id = target_match_id;

  if target_match_status = 'completed' and target_result_type <> 'no_result' then
    select count(*)::integer into player_of_match_count
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

create or replace function public.validate_match_innings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
  expected_overs integer;
  minimum_players integer;
  maximum_players integer;
begin
  select * into match_record
  from public.matches
  where id = new.match_id;

  if new.batting_season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id)
    or new.bowling_season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id) then
    raise exception 'innings teams must be the match teams';
  end if;

  if new.batting_season_team_id = new.bowling_season_team_id then
    raise exception 'innings teams must be different';
  end if;

  select s.match_min_players, s.match_max_players
  into minimum_players, maximum_players
  from public.seasons s
  where s.id = match_record.season_id;

  select least(
    count(*) filter (where season_team_id = match_record.home_season_team_id)::integer,
    count(*) filter (where season_team_id = match_record.away_season_team_id)::integer
  ) into expected_overs
  from public.match_lineups
  where match_id = new.match_id;

  if expected_overs not between minimum_players and maximum_players
    or new.overs_limit is distinct from expected_overs then
    raise exception 'innings overs must match the selected player lineups';
  end if;

  if new.balls_per_over is distinct from (
    select s.balls_per_over
    from public.seasons s
    where s.id = match_record.season_id
  ) then
    raise exception 'innings balls per over must match the season rule';
  end if;

  if new.max_overs_per_player is distinct from (
    select s.max_overs_per_player
    from public.seasons s
    where s.id = match_record.season_id
  ) then
    raise exception 'innings bowler limit must match the season rule';
  end if;

  return new;
end;
$$;

create trigger match_innings_validate
before insert or update on public.match_innings
for each row execute function public.validate_match_innings();

create or replace function public.validate_match_over_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  match_record public.matches%rowtype;
  existing_bowling_overs integer;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = new.innings_id;

  select m.* into match_record
  from public.matches m
  where m.id = innings_record.match_id;

  if new.over_number > innings_record.overs_limit then
    raise exception 'over number exceeds the innings limit';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_record.id
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = new.batting_slot_season_roster_id
  ) then
    raise exception 'batting slot player must be in the batting lineup';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_record.id
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.bowler_season_roster_id
  ) then
    raise exception 'bowler must be in the bowling lineup';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_record.id
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.wicketkeeper_season_roster_id
  ) then
    raise exception 'wicketkeeper must be in the bowling lineup';
  end if;

  select count(*)::integer into existing_bowling_overs
  from public.match_over_assignments moa
  where moa.innings_id = new.innings_id
    and moa.bowler_season_roster_id = new.bowler_season_roster_id
    and moa.id <> new.id;

  if existing_bowling_overs >= innings_record.max_overs_per_player then
    raise exception 'bowler exceeds the season over limit';
  end if;

  return new;
end;
$$;

create trigger match_over_assignments_validate
before insert or update on public.match_over_assignments
for each row execute function public.validate_match_over_assignment();

create or replace function public.validate_match_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
  match_id_value uuid;
begin
  select moa.* into assignment_record
  from public.match_over_assignments moa
  where moa.id = new.over_assignment_id;

  if assignment_record.innings_id is distinct from new.innings_id then
    raise exception 'delivery innings must match the over assignment';
  end if;

  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = new.innings_id;

  select match_id into match_id_value
  from public.match_innings
  where id = new.innings_id;

  if new.bowler_season_roster_id is distinct from assignment_record.bowler_season_roster_id then
    raise exception 'delivery bowler must match the over assignment';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = new.striker_season_roster_id
  ) then
    raise exception 'striker must belong to the batting lineup';
  end if;

  if new.non_striker_season_roster_id is not null and not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.batting_season_team_id
      and ml.season_roster_id = new.non_striker_season_roster_id
  ) then
    raise exception 'non-striker must belong to the batting lineup';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.bowler_season_roster_id
  ) then
    raise exception 'bowler must belong to the bowling lineup';
  end if;

  if new.fielder_season_roster_id is not null and not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = match_id_value
      and ml.season_team_id = innings_record.bowling_season_team_id
      and ml.season_roster_id = new.fielder_season_roster_id
  ) then
    raise exception 'fielder must belong to the bowling lineup';
  end if;

  if new.delivery_type = 'legal' and new.extra_runs <> 0 then
    raise exception 'legal deliveries cannot have extras in this scoring model';
  end if;

  if new.delivery_type in ('wide', 'no_ball') and new.extra_runs < 1 then
    raise exception 'wides and no-balls must record at least one extra run';
  end if;

  if new.delivery_type = 'no_ball' and new.batter_runs not in (0, 1, 2, 4, 6) then
    raise exception 'no-balls support 0, 1, 2, 4, or 6 batter runs';
  end if;

  if new.delivery_type = 'dead_ball' and (new.batter_runs <> 0 or new.extra_runs <> 0 or new.is_wicket) then
    raise exception 'dead balls cannot score runs or wickets';
  end if;

  if new.is_wicket and new.dismissed_season_roster_id is distinct from new.striker_season_roster_id then
    raise exception 'dismissed player must be the striker';
  end if;

  if new.dismissal_type = 'stumped'
    and new.fielder_season_roster_id is distinct from assignment_record.wicketkeeper_season_roster_id then
    raise exception 'stumpings must be credited to the wicketkeeper';
  end if;

  if new.dismissal_type in ('caught', 'stumped', 'run_out') and new.fielder_season_roster_id is null then
    raise exception 'this dismissal requires a fielder';
  end if;

  if new.dismissal_type in ('bowled', 'hit_wicket') and new.fielder_season_roster_id is not null then
    raise exception 'this dismissal cannot have a fielder';
  end if;

  return new;
end;
$$;

create trigger match_deliveries_validate
before insert or update on public.match_deliveries
for each row execute function public.validate_match_delivery();

create or replace function public.resequence_match_over(target_over_assignment_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  with numbered as (
    select
      md.id,
      md.delivery_type,
      sum(case when md.delivery_type = 'legal' then 1 else 0 end)
        over (order by md.delivery_sequence rows between unbounded preceding and current row) as legal_number
    from public.match_deliveries md
    where md.over_assignment_id = target_over_assignment_id
  )
  update public.match_deliveries md
  set legal_ball_number = case when numbered.delivery_type = 'legal' then numbered.legal_number else null end
  from numbered
  where md.id = numbered.id;
$$;

create or replace function public.start_match(
  target_match_id uuid,
  first_batting_season_team_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
  balls_per_over_value integer;
  max_overs_per_player_value integer;
  minimum_players integer;
  maximum_players integer;
  home_players integer;
  away_players integer;
  overs_value integer;
  innings_id_value uuid;
begin
  select m.* into match_record
  from public.matches m
  where m.id = target_match_id
  for update;

  if match_record.id is null then
    raise exception 'match not found';
  end if;

  if match_record.status <> 'scheduled' then
    raise exception 'only scheduled matches can be started';
  end if;

  if first_batting_season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id) then
    raise exception 'first batting team must be one of the match teams';
  end if;

  select s.balls_per_over, s.max_overs_per_player, s.match_min_players, s.match_max_players
  into balls_per_over_value, max_overs_per_player_value, minimum_players, maximum_players
  from public.seasons s
  where s.id = match_record.season_id;

  select
    count(*) filter (where ml.season_team_id = match_record.home_season_team_id)::integer,
    count(*) filter (where ml.season_team_id = match_record.away_season_team_id)::integer
  into home_players, away_players
  from public.match_lineups ml
  where ml.match_id = target_match_id;

  if home_players not between minimum_players and maximum_players
    or away_players not between minimum_players and maximum_players then
    raise exception 'both teams must have a valid number of selected players for the season';
  end if;

  overs_value := least(home_players, away_players);

  insert into public.match_innings (
    match_id,
    innings_number,
    batting_season_team_id,
    bowling_season_team_id,
    overs_limit,
    balls_per_over,
    legal_balls_limit,
    max_overs_per_player,
    status
  ) values (
    target_match_id,
    1,
    first_batting_season_team_id,
    case
      when first_batting_season_team_id = match_record.home_season_team_id then match_record.away_season_team_id
      else match_record.home_season_team_id
    end,
    overs_value,
    balls_per_over_value,
    overs_value * balls_per_over_value,
    max_overs_per_player_value,
    'live'
  )
  returning id into innings_id_value;

  update public.matches
  set status = 'live',
      result_type = null,
      winner_season_team_id = null,
      updated_at = now()
  where id = target_match_id;

  return innings_id_value;
end;
$$;

create or replace function public.set_match_over_assignment(
  target_innings_id uuid,
  target_over_number integer,
  target_batting_slot_season_roster_id uuid,
  target_bowler_season_roster_id uuid,
  target_wicketkeeper_season_roster_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  assignment_id_value uuid;
  match_id_value uuid;
  previous_assignment_id uuid;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = target_innings_id
  for update;

  if innings_record.id is null or innings_record.status <> 'live' then
    raise exception 'innings is not live';
  end if;

  if target_over_number < 1 or target_over_number > innings_record.overs_limit then
    raise exception 'over number is outside the innings limit';
  end if;

  select match_id into match_id_value
  from public.match_innings
  where id = target_innings_id;

  if target_over_number > 1 then
    select moa.id into previous_assignment_id
    from public.match_over_assignments moa
    where moa.innings_id = target_innings_id
      and moa.over_number = target_over_number - 1;

    if previous_assignment_id is null then
      raise exception 'the previous over must be assigned first';
    end if;

    if (
      select count(*)
      from public.match_deliveries md
      where md.over_assignment_id = previous_assignment_id
        and md.delivery_type = 'legal'
    ) < innings_record.balls_per_over then
      raise exception 'the previous over must contain six legal balls';
    end if;
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    where moa.innings_id = target_innings_id
      and moa.over_number = target_over_number
  ) then
    raise exception 'an over cannot be reassigned after scoring has started';
  end if;

  insert into public.match_over_assignments (
    innings_id,
    over_number,
    batting_slot_season_roster_id,
    bowler_season_roster_id,
    wicketkeeper_season_roster_id
  ) values (
    target_innings_id,
    target_over_number,
    target_batting_slot_season_roster_id,
    target_bowler_season_roster_id,
    target_wicketkeeper_season_roster_id
  )
  on conflict (innings_id, over_number) do update
  set batting_slot_season_roster_id = excluded.batting_slot_season_roster_id,
      bowler_season_roster_id = excluded.bowler_season_roster_id,
      wicketkeeper_season_roster_id = excluded.wicketkeeper_season_roster_id,
      updated_at = now()
  returning id into assignment_id_value;

  return assignment_id_value;
end;
$$;

create or replace function public.record_match_delivery(
  target_over_assignment_id uuid,
  target_striker_season_roster_id uuid,
  target_non_striker_season_roster_id uuid,
  target_delivery_type text,
  target_batter_runs integer default 0,
  target_extra_runs integer default 0,
  target_is_wicket boolean default false,
  target_dismissed_season_roster_id uuid default null,
  target_dismissal_type text default null,
  target_fielder_season_roster_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_record public.match_over_assignments%rowtype;
  innings_record public.match_innings%rowtype;
  match_status text;
  current_legal_balls integer;
  delivery_id_value uuid;
  sequence_value integer;
begin
  select moa.* into assignment_record
  from public.match_over_assignments moa
  where moa.id = target_over_assignment_id
  for update;

  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = assignment_record.innings_id
  for update;

  select status into match_status
  from public.matches
  where id = innings_record.match_id;

  if innings_record.status <> 'live' or match_status <> 'live' then
    raise exception 'match innings is not live';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    join public.match_over_assignments moa on moa.id = md.over_assignment_id
    where moa.innings_id = innings_record.id
      and moa.over_number > assignment_record.over_number
  ) then
    raise exception 'a later over has already been scored';
  end if;

  if assignment_record.over_number > 1 and exists (
    select 1
    from public.match_over_assignments previous
    where previous.innings_id = innings_record.id
      and previous.over_number = assignment_record.over_number - 1
      and (
        select count(*)
        from public.match_deliveries md
        where md.over_assignment_id = previous.id
          and md.delivery_type = 'legal'
      ) < innings_record.balls_per_over
  ) then
    raise exception 'the previous over must contain six legal balls';
  end if;

  select count(*)::integer into current_legal_balls
  from public.match_deliveries md
  where md.over_assignment_id = assignment_record.id
    and md.delivery_type = 'legal';

  if current_legal_balls >= innings_record.balls_per_over then
    raise exception 'this over already contains six legal balls';
  end if;

  if target_delivery_type not in ('legal', 'wide', 'no_ball', 'dead_ball') then
    raise exception 'invalid delivery type';
  end if;

  if target_delivery_type = 'legal' and target_extra_runs <> 0 then
    raise exception 'legal deliveries cannot have extras';
  end if;

  if target_delivery_type in ('wide', 'no_ball') and target_extra_runs < 1 then
    raise exception 'wides and no-balls require an extra run';
  end if;

  if target_delivery_type = 'no_ball' and target_batter_runs not in (0, 1, 2, 4, 6) then
    raise exception 'no-balls support 0, 1, 2, 4, or 6 batter runs';
  end if;

  if target_delivery_type = 'dead_ball'
    and (target_batter_runs <> 0 or target_extra_runs <> 0 or target_is_wicket) then
    raise exception 'dead balls cannot score runs or wickets';
  end if;

  if exists (
    select 1
    from public.match_deliveries md
    where md.innings_id = innings_record.id
      and md.dismissed_season_roster_id = target_striker_season_roster_id
  ) then
    raise exception 'a dismissed player cannot return to the crease';
  end if;

  select coalesce(max(delivery_sequence), 0) + 1 into sequence_value
  from public.match_deliveries md
  where md.innings_id = innings_record.id;

  insert into public.match_deliveries (
    innings_id,
    over_assignment_id,
    delivery_sequence,
    legal_ball_number,
    striker_season_roster_id,
    non_striker_season_roster_id,
    bowler_season_roster_id,
    delivery_type,
    batter_runs,
    extra_runs,
    is_wicket,
    dismissed_season_roster_id,
    dismissal_type,
    fielder_season_roster_id
  ) values (
    innings_record.id,
    assignment_record.id,
    sequence_value,
    case when target_delivery_type = 'legal' then current_legal_balls + 1 else null end,
    target_striker_season_roster_id,
    target_non_striker_season_roster_id,
    assignment_record.bowler_season_roster_id,
    target_delivery_type,
    target_batter_runs,
    target_extra_runs,
    target_is_wicket,
    target_dismissed_season_roster_id,
    target_dismissal_type,
    target_fielder_season_roster_id
  )
  returning id into delivery_id_value;

  return delivery_id_value;
end;
$$;

create or replace function public.update_current_over_delivery(
  target_delivery_id uuid,
  target_striker_season_roster_id uuid,
  target_non_striker_season_roster_id uuid,
  target_delivery_type text,
  target_batter_runs integer default 0,
  target_extra_runs integer default 0,
  target_is_wicket boolean default false,
  target_dismissed_season_roster_id uuid default null,
  target_dismissal_type text default null,
  target_fielder_season_roster_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  delivery_record public.match_deliveries%rowtype;
  current_over_number integer;
  current_legal_balls integer;
begin
  select md.* into delivery_record
  from public.match_deliveries md
  where md.id = target_delivery_id
  for update;

  select max(moa.over_number) into current_over_number
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = delivery_record.innings_id;

  if delivery_record.id is null or delivery_record.over_assignment_id is null then
    raise exception 'delivery not found';
  end if;

  if (select status from public.match_innings where id = delivery_record.innings_id) <> 'live'
    or current_over_number <> (
      select moa.over_number
      from public.match_over_assignments moa
      where moa.id = delivery_record.over_assignment_id
    ) then
    raise exception 'only deliveries from the current over can be edited';
  end if;

  select count(*)::integer into current_legal_balls
  from public.match_deliveries md
  where md.over_assignment_id = delivery_record.over_assignment_id
    and md.delivery_type = 'legal';

  if current_legal_balls >= (select balls_per_over from public.match_innings where id = delivery_record.innings_id) then
    raise exception 'completed overs cannot be edited';
  end if;

  update public.match_deliveries
  set striker_season_roster_id = target_striker_season_roster_id,
      non_striker_season_roster_id = target_non_striker_season_roster_id,
      delivery_type = target_delivery_type,
      batter_runs = target_batter_runs,
      extra_runs = target_extra_runs,
      is_wicket = target_is_wicket,
      dismissed_season_roster_id = target_dismissed_season_roster_id,
      dismissal_type = target_dismissal_type,
      fielder_season_roster_id = target_fielder_season_roster_id,
      updated_at = now()
  where id = target_delivery_id;

  perform public.resequence_match_over(delivery_record.over_assignment_id);
  return target_delivery_id;
end;
$$;

create or replace function public.delete_current_over_delivery(target_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  delivery_record public.match_deliveries%rowtype;
  current_over_number integer;
  delivery_over_number integer;
begin
  select md.* into delivery_record
  from public.match_deliveries md
  where md.id = target_delivery_id
  for update;

  select moa.over_number into delivery_over_number
  from public.match_over_assignments moa
  where moa.id = delivery_record.over_assignment_id;

  select max(moa.over_number) into current_over_number
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = delivery_record.innings_id;

  if delivery_record.id is null or delivery_over_number <> current_over_number then
    raise exception 'only deliveries from the current over can be deleted';
  end if;

  if (select status from public.match_innings where id = delivery_record.innings_id) <> 'live' then
    raise exception 'only live innings can be corrected';
  end if;

  delete from public.match_deliveries where id = target_delivery_id;
  perform public.resequence_match_over(delivery_record.over_assignment_id);
end;
$$;

create or replace function public.complete_match_innings(target_innings_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  innings_record public.match_innings%rowtype;
  innings_score integer;
  legal_ball_count integer;
  all_out boolean;
  target_reached boolean;
  batting_lineup_count integer;
  next_innings_id uuid;
begin
  select mi.* into innings_record
  from public.match_innings mi
  where mi.id = target_innings_id
  for update;

  if innings_record.status <> 'live' then
    raise exception 'innings is already completed';
  end if;

  select
    count(*) filter (where md.delivery_type = 'legal')::integer,
    coalesce(sum(md.batter_runs + md.extra_runs)::integer, 0)
  into legal_ball_count, innings_score
  from public.match_deliveries md
  where md.innings_id = target_innings_id;

  select not exists (
    select 1
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.batting_season_team_id
      and not exists (
        select 1
        from public.match_deliveries dismissed
        where dismissed.innings_id = target_innings_id
          and dismissed.dismissed_season_roster_id = ml.season_roster_id
      )
  ) into all_out;

  target_reached := innings_record.target_score is not null and innings_score >= innings_record.target_score;

  if legal_ball_count < innings_record.legal_balls_limit and not all_out and not target_reached then
    raise exception 'innings has not reached its ending condition';
  end if;

  if legal_ball_count = innings_record.legal_balls_limit then
    if (
      select count(*)
      from public.match_over_assignments moa
      where moa.innings_id = target_innings_id
    ) <> innings_record.overs_limit
    or exists (
      select 1
      from public.match_over_assignments moa
      where moa.innings_id = target_innings_id
      group by moa.bowler_season_roster_id
      having count(*) > innings_record.max_overs_per_player
    ) then
      raise exception 'a full innings exceeds the season over limit';
    end if;

    select count(*)::integer into batting_lineup_count
    from public.match_lineups ml
    where ml.match_id = innings_record.match_id
      and ml.season_team_id = innings_record.batting_season_team_id;

    if batting_lineup_count = innings_record.overs_limit
      and exists (
        select 1
        from public.match_lineups ml
        where ml.match_id = innings_record.match_id
          and ml.season_team_id = innings_record.batting_season_team_id
          and not exists (
            select 1
            from public.match_over_assignments moa
            where moa.innings_id = target_innings_id
              and moa.batting_slot_season_roster_id = ml.season_roster_id
          )
      ) then
      raise exception 'a full innings requires one batting slot for every player';
    end if;
  end if;

  update public.match_innings
  set status = 'completed',
      completed_at = now(),
      updated_at = now()
  where id = target_innings_id;

  if innings_record.innings_number = 1 then
    insert into public.match_innings (
      match_id,
      innings_number,
      batting_season_team_id,
      bowling_season_team_id,
      overs_limit,
      balls_per_over,
      legal_balls_limit,
      max_overs_per_player,
      target_score,
      status
    ) values (
      innings_record.match_id,
      2,
      innings_record.bowling_season_team_id,
      innings_record.batting_season_team_id,
      innings_record.overs_limit,
      innings_record.balls_per_over,
      innings_record.legal_balls_limit,
      innings_record.max_overs_per_player,
      innings_score + 1,
      'live'
    ) returning id into next_innings_id;

    return next_innings_id;
  end if;

  return null;
end;
$$;

create or replace function public.finalize_match(
  target_match_id uuid,
  player_of_match_lineup_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
  first_score integer;
  second_score integer;
  result_value text;
  winner_value uuid;
begin
  select m.* into match_record
  from public.matches m
  where m.id = target_match_id
  for update;

  if match_record.status <> 'live' then
    raise exception 'only live matches can be finalized';
  end if;

  if not exists (
    select 1
    from public.match_innings mi
    where mi.match_id = target_match_id
      and mi.innings_number = 1
      and mi.status = 'completed'
  ) or not exists (
    select 1
    from public.match_innings mi
    where mi.match_id = target_match_id
      and mi.innings_number = 2
      and mi.status = 'completed'
  ) then
    raise exception 'both innings must be completed before finalization';
  end if;

  if not exists (
    select 1
    from public.match_lineups ml
    where ml.id = player_of_match_lineup_id
      and ml.match_id = target_match_id
  ) then
    raise exception 'player of the match must be selected from this match';
  end if;

  select coalesce(sum(md.batter_runs + md.extra_runs)::integer, 0)
  into first_score
  from public.match_deliveries md
  join public.match_innings mi on mi.id = md.innings_id
  where mi.match_id = target_match_id
    and mi.innings_number = 1;

  select coalesce(sum(md.batter_runs + md.extra_runs)::integer, 0)
  into second_score
  from public.match_deliveries md
  join public.match_innings mi on mi.id = md.innings_id
  where mi.match_id = target_match_id
    and mi.innings_number = 2;

  if second_score > first_score then
    result_value := 'win';
    select mi.batting_season_team_id into winner_value
    from public.match_innings mi
    where mi.match_id = target_match_id and mi.innings_number = 2;
  elsif first_score > second_score then
    result_value := 'win';
    select mi.batting_season_team_id into winner_value
    from public.match_innings mi
    where mi.match_id = target_match_id and mi.innings_number = 1;
  else
    result_value := 'tie';
    winner_value := null;
  end if;

  insert into public.match_player_stats (
    match_lineup_id,
    runs,
    balls_faced,
    fours,
    sixes,
    balls_bowled,
    runs_conceded,
    wickets,
    catches,
    stumpings,
    is_player_of_match
  )
  select
    ml.id,
    coalesce(sum(case when md.striker_season_roster_id = ml.season_roster_id then md.batter_runs else 0 end)::integer, 0),
    count(*) filter (where md.striker_season_roster_id = ml.season_roster_id and md.delivery_type = 'legal')::integer,
    count(*) filter (where md.striker_season_roster_id = ml.season_roster_id and md.batter_runs = 4)::integer,
    count(*) filter (where md.striker_season_roster_id = ml.season_roster_id and md.batter_runs = 6)::integer,
    count(*) filter (where md.bowler_season_roster_id = ml.season_roster_id and md.delivery_type = 'legal')::integer,
    coalesce(sum(case when md.bowler_season_roster_id = ml.season_roster_id then md.batter_runs + md.extra_runs else 0 end)::integer, 0),
    count(*) filter (
      where md.bowler_season_roster_id = ml.season_roster_id
        and md.is_wicket
        and md.dismissal_type in ('bowled', 'caught', 'stumped', 'hit_wicket')
    )::integer,
    count(*) filter (where md.fielder_season_roster_id = ml.season_roster_id and md.dismissal_type = 'caught')::integer,
    count(*) filter (where md.fielder_season_roster_id = ml.season_roster_id and md.dismissal_type = 'stumped')::integer,
    ml.id = player_of_match_lineup_id
  from public.match_lineups ml
  left join public.match_deliveries md
    on md.innings_id in (
      select mi.id from public.match_innings mi where mi.match_id = target_match_id
    )
  where ml.match_id = target_match_id
  group by ml.id, ml.season_roster_id;

  update public.match_player_stats
  set is_player_of_match = (match_lineup_id = player_of_match_lineup_id),
      updated_at = now()
  where match_lineup_id in (
    select ml.id from public.match_lineups ml where ml.match_id = target_match_id
  );

  update public.matches
  set status = 'completed',
      result_type = result_value,
      winner_season_team_id = winner_value,
      updated_at = now()
  where id = target_match_id;

  return jsonb_build_object(
    'result_type', result_value,
    'winner_season_team_id', winner_value,
    'first_score', first_score,
    'second_score', second_score
  );
end;
$$;

create or replace function public.mark_match_no_result(target_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
begin
  select m.* into match_record
  from public.matches m
  where m.id = target_match_id
  for update;

  if match_record.status <> 'live' then
    raise exception 'only live matches can be marked no result';
  end if;

  insert into public.match_player_stats (match_lineup_id)
  select ml.id
  from public.match_lineups ml
  where ml.match_id = target_match_id
  on conflict (match_lineup_id) do update
  set runs = 0,
      balls_faced = 0,
      fours = 0,
      sixes = 0,
      balls_bowled = 0,
      runs_conceded = 0,
      wickets = 0,
      catches = 0,
      stumpings = 0,
      is_player_of_match = false,
      updated_at = now();

  update public.matches
  set status = 'completed',
      result_type = 'no_result',
      winner_season_team_id = null,
      updated_at = now()
  where id = target_match_id;
end;
$$;

create or replace function public.get_match_scoring_state(target_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  state jsonb;
begin
  select jsonb_build_object(
    'match', (
      select jsonb_build_object(
        'id', m.id,
        'season_id', m.season_id,
        'status', m.status,
        'result_type', m.result_type,
        'winner_season_team_id', m.winner_season_team_id,
        'home_season_team_id', m.home_season_team_id,
        'away_season_team_id', m.away_season_team_id,
        'home_team_name', home_team.name,
        'away_team_name', away_team.name,
        'match_date', m.match_date,
        'venue', m.venue,
        'balls_per_over', s.balls_per_over,
        'max_overs_per_player', s.max_overs_per_player
      )
      from public.matches m
      join public.seasons s on s.id = m.season_id
      join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
      join public.teams home_team on home_team.id = home_season_team.team_id
      join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
      join public.teams away_team on away_team.id = away_season_team.team_id
      where m.id = target_match_id
    ),
    'lineups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ml.id,
        'season_team_id', ml.season_team_id,
        'season_roster_id', ml.season_roster_id,
        'player_id', sr.player_id,
        'player_name', p.display_name,
        'is_captain', ml.is_captain
      ) order by ml.season_team_id, p.display_name)
      from public.match_lineups ml
      join public.season_rosters sr on sr.id = ml.season_roster_id
      join public.players p on p.id = sr.player_id
      where ml.match_id = target_match_id
    ), '[]'::jsonb),
    'innings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mi.id,
        'innings_number', mi.innings_number,
        'batting_season_team_id', mi.batting_season_team_id,
        'bowling_season_team_id', mi.bowling_season_team_id,
        'overs_limit', mi.overs_limit,
        'balls_per_over', mi.balls_per_over,
        'legal_balls_limit', mi.legal_balls_limit,
        'max_overs_per_player', mi.max_overs_per_player,
        'target_score', mi.target_score,
        'status', mi.status,
        'overs', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', moa.id,
            'over_number', moa.over_number,
            'batting_slot_season_roster_id', moa.batting_slot_season_roster_id,
            'bowler_season_roster_id', moa.bowler_season_roster_id,
            'wicketkeeper_season_roster_id', moa.wicketkeeper_season_roster_id,
            'batting_slot_name', batting_player.display_name,
            'bowler_name', bowler_player.display_name,
            'wicketkeeper_name', keeper_player.display_name,
            'deliveries', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', md.id,
                'delivery_sequence', md.delivery_sequence,
                'legal_ball_number', md.legal_ball_number,
                'striker_season_roster_id', md.striker_season_roster_id,
                'non_striker_season_roster_id', md.non_striker_season_roster_id,
                'bowler_season_roster_id', md.bowler_season_roster_id,
                'delivery_type', md.delivery_type,
                'batter_runs', md.batter_runs,
                'extra_runs', md.extra_runs,
                'is_wicket', md.is_wicket,
                'dismissed_season_roster_id', md.dismissed_season_roster_id,
                'dismissal_type', md.dismissal_type,
                'fielder_season_roster_id', md.fielder_season_roster_id
              ) order by md.delivery_sequence)
              from public.match_deliveries md
              where md.over_assignment_id = moa.id
            ), '[]'::jsonb)
          ) order by moa.over_number)
          from public.match_over_assignments moa
          join public.season_rosters batting_roster on batting_roster.id = moa.batting_slot_season_roster_id
          join public.players batting_player on batting_player.id = batting_roster.player_id
          join public.season_rosters bowler_roster on bowler_roster.id = moa.bowler_season_roster_id
          join public.players bowler_player on bowler_player.id = bowler_roster.player_id
          join public.season_rosters keeper_roster on keeper_roster.id = moa.wicketkeeper_season_roster_id
          join public.players keeper_player on keeper_player.id = keeper_roster.player_id
          where moa.innings_id = mi.id
        ), '[]'::jsonb)
      ) order by mi.innings_number)
      from public.match_innings mi
      where mi.match_id = target_match_id
    ), '[]'::jsonb)
  ) into state;

  return state;
end;
$$;

grant execute on function public.start_match(uuid, uuid) to anon, authenticated;
grant execute on function public.set_match_over_assignment(uuid, integer, uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.record_match_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.update_current_over_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.delete_current_over_delivery(uuid) to anon, authenticated;
grant execute on function public.complete_match_innings(uuid) to anon, authenticated;
grant execute on function public.finalize_match(uuid, uuid) to anon, authenticated;
grant execute on function public.mark_match_no_result(uuid) to anon, authenticated;
grant execute on function public.get_match_scoring_state(uuid) to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.match_innings,
      public.match_over_assignments,
      public.match_deliveries;
  end if;
end;
$$;

drop function if exists public.get_public_matches_for_season(uuid);

create function public.get_public_matches_for_season(target_season_id uuid)
returns table (
  match_id uuid,
  season_id uuid,
  home_season_team_id uuid,
  home_team_name text,
  away_season_team_id uuid,
  away_team_name text,
  match_date timestamptz,
  venue text,
  status text,
  result_type text,
  winner_team_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id,
    m.season_id,
    m.home_season_team_id,
    home_team.name,
    m.away_season_team_id,
    away_team.name,
    m.match_date,
    m.venue,
    m.status,
    m.result_type,
    winner_team.name
  from public.matches m
  join public.season_teams home_season_team on home_season_team.id = m.home_season_team_id
  join public.teams home_team on home_team.id = home_season_team.team_id
  join public.season_teams away_season_team on away_season_team.id = m.away_season_team_id
  join public.teams away_team on away_team.id = away_season_team.team_id
  join public.seasons s on s.id = m.season_id
  left join public.season_teams winner_season_team on winner_season_team.id = m.winner_season_team_id
  left join public.teams winner_team on winner_team.id = winner_season_team.team_id
  where m.season_id = target_season_id
    and (
      m.status <> 'draft'
      or public.has_league_role(s.league_id, array['admin'])
    )
  order by m.match_date asc nulls last, home_team.name, away_team.name;
$$;

grant execute on function public.get_public_matches_for_season(uuid) to anon, authenticated;
