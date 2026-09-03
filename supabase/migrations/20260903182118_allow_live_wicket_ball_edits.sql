begin;

do $migration$
declare
  function_definition text;
  old_fragment constant text := 'if batting_turn_record.phase = ''initial'' and not has_wicket and legal_ball_count < 6 then';
  new_fragment constant text := 'if batting_turn_record.phase = ''initial'' and not target_is_wicket and legal_ball_count < 6 then';
begin
  select pg_get_functiondef('public.update_current_over_delivery(uuid,uuid,uuid,text,integer,integer,boolean,uuid,text,uuid)'::regprocedure)
  into function_definition;

  if position(new_fragment in function_definition) > 0 then
    return;
  end if;

  if position(old_fragment in function_definition) = 0 then
    raise exception 'live delivery edit guard could not be updated safely';
  end if;

  execute replace(function_definition, old_fragment, new_fragment);
end;
$migration$;

commit;

