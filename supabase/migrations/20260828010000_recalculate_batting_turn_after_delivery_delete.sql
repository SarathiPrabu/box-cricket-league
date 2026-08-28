create or replace function public.delete_current_over_delivery(target_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  delivery_record public.match_deliveries%rowtype;
  batting_turn_record public.match_batting_turns%rowtype;
  delivery_over_number integer;
  current_over_number integer;
  later_turn public.match_batting_turns%rowtype;
begin
  select md.* into delivery_record
  from public.match_deliveries md
  where md.id = target_delivery_id
  for update;

  if delivery_record.id is null or delivery_record.batting_turn_id is null then
    raise exception 'delivery not found or has no batting turn';
  end if;

  select moa.over_number into delivery_over_number
  from public.match_over_assignments moa
  where moa.id = delivery_record.over_assignment_id;

  select max(moa.over_number) into current_over_number
  from public.match_deliveries md
  join public.match_over_assignments moa on moa.id = md.over_assignment_id
  where md.innings_id = delivery_record.innings_id;

  if delivery_over_number <> current_over_number then
    raise exception 'only deliveries from the current over can be deleted';
  end if;

  if (select status from public.match_innings where id = delivery_record.innings_id) <> 'live' then
    raise exception 'only live innings can be corrected';
  end if;

  select mbt.* into batting_turn_record
  from public.match_batting_turns mbt
  where mbt.id = delivery_record.batting_turn_id
  for update;

  delete from public.match_deliveries where id = target_delivery_id;
  perform public.resequence_match_over(delivery_record.over_assignment_id);

  -- A wicket delivery can have created an empty replacement turn. Once the
  -- wicket is undone, remove only those empty downstream turns so the
  -- affected batter can safely become active again. Never remove a turn that
  -- already has deliveries.
  for later_turn in
    select mbt.*
    from public.match_batting_turns mbt
    where mbt.innings_id = batting_turn_record.innings_id
      and mbt.turn_number > batting_turn_record.turn_number
      and not exists (
        select 1
        from public.match_deliveries md
        where md.batting_turn_id = mbt.id
      )
    order by mbt.turn_number desc
  loop
    delete from public.match_batting_turns where id = later_turn.id;
  end loop;

  -- Recompute the affected turn from its remaining deliveries. Later turns
  -- with deliveries are intentionally left unchanged.
  perform public.refresh_match_batting_turn(batting_turn_record.id);
end;
$$;

grant execute on function public.delete_current_over_delivery(uuid) to anon, authenticated;
