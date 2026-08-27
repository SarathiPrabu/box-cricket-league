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
  if match_record.status not in ('scheduled', 'live') then raise exception 'only scheduled or live matches can be recorded as a forfeit'; end if;
  if forfeiting_season_team_id not in (match_record.home_season_team_id, match_record.away_season_team_id) then raise exception 'forfeiting team must be one of the match teams'; end if;
  if trimmed_reason is null then raise exception 'a forfeit reason is required'; end if;
  winning_season_team_id := case when forfeiting_season_team_id = match_record.home_season_team_id then match_record.away_season_team_id else match_record.home_season_team_id end;
  update public.matches
  set status = 'completed', result_type = 'forfeit', winner_season_team_id = winning_season_team_id,
      forfeiting_season_team_id = record_match_forfeit.forfeiting_season_team_id,
      forfeit_reason = trimmed_reason, updated_at = now()
  where id = target_match_id;
  return jsonb_build_object('result_type', 'forfeit', 'winner_season_team_id', winning_season_team_id,
    'forfeiting_season_team_id', forfeiting_season_team_id, 'forfeit_reason', trimmed_reason);
end;
$$;

revoke all on function public.record_match_forfeit(uuid, uuid, text) from public;
grant execute on function public.record_match_forfeit(uuid, uuid, text) to anon, authenticated;
