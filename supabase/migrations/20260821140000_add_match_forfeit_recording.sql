-- Add a first-class forfeit result. Forfeits complete the match without
-- creating player statistics or requiring completed innings.
alter table public.matches
  add column if not exists forfeiting_season_team_id uuid references public.season_teams(id) on delete set null,
  add column if not exists forfeit_reason text;

alter table public.matches
  drop constraint if exists matches_result_type_check,
  add constraint matches_result_type_check
    check (result_type is null or result_type in ('win', 'tie', 'no_result', 'forfeit'));

do $functions$
declare
  definition text;
begin
  select pg_get_functiondef('public.validate_match()'::regprocedure) into definition;
  definition := replace(definition, 'if new.result_type <> ''no_result'' then', 'if new.result_type not in (''no_result'', ''forfeit'') then');
  if position('forfeit' in definition) = 0 then raise exception 'validate_match replacement failed'; end if;
  execute definition;

  select pg_get_functiondef('public.validate_completed_match_player_of_match()'::regprocedure) into definition;
  definition := replace(definition, 'if target_match_status = ''completed'' and target_result_type <> ''no_result'' then', 'if target_match_status = ''completed'' and target_result_type not in (''no_result'', ''forfeit'') then');
  if position('forfeit' in definition) = 0 then raise exception 'player-of-match validation replacement failed'; end if;
  execute definition;
end;
$functions$;

create or replace function public.record_match_forfeit(
  target_match_id uuid,
  forfeiting_season_team_id uuid,
  target_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  match_record public.matches%rowtype;
  winning_season_team_id uuid;
  trimmed_reason text := nullif(trim(target_reason), '');
begin
  select * into match_record from public.matches where id = target_match_id for update;
  if match_record.id is null then raise exception 'match not found'; end if;
  if match_record.status <> 'live' then raise exception 'only live matches can be recorded as a forfeit'; end if;
  if forfeiting_season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id) then
    raise exception 'forfeiting team must be one of the match teams';
  end if;
  if trimmed_reason is null then raise exception 'a forfeit reason is required'; end if;

  winning_season_team_id := case
    when forfeiting_season_team_id = match_record.home_season_team_id then match_record.away_season_team_id
    else match_record.home_season_team_id
  end;

  update public.matches
  set status = 'completed', result_type = 'forfeit', winner_season_team_id = winning_season_team_id,
      forfeiting_season_team_id = forfeiting_season_team_id, forfeit_reason = trimmed_reason, updated_at = now()
  where id = target_match_id;

  return jsonb_build_object('result_type', 'forfeit', 'winner_season_team_id', winning_season_team_id,
    'forfeiting_season_team_id', forfeiting_season_team_id, 'forfeit_reason', trimmed_reason);
end;
$$;

revoke all on function public.record_match_forfeit(uuid, uuid, text) from public;
grant execute on function public.record_match_forfeit(uuid, uuid, text) to anon, authenticated;

comment on column public.matches.forfeiting_season_team_id is 'Team that forfeited a match when result_type is forfeit.';
comment on column public.matches.forfeit_reason is 'Recorded reason for a match forfeit.';
