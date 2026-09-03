begin;

alter table public.match_deliveries
  drop constraint if exists match_deliveries_dismissal_type_check;

alter table public.match_deliveries
  add constraint match_deliveries_dismissal_type_check check (
    dismissal_type is null
    or dismissal_type in ('bowled', 'caught', 'caught_and_bowled', 'stumped', 'hit_wicket', 'hit_out_of_field')
  ) not valid;

do $$
begin
  alter table public.match_deliveries
    validate constraint match_deliveries_dismissal_type_check;
end;
$$;

create or replace function public.validate_match_dismissal_type()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.dismissal_type = 'run_out' then
    raise exception 'run out is no longer supported';
  end if;

  if new.dismissal_type = 'hit_out_of_field'
    and new.fielder_season_roster_id is not null then
    raise exception 'hit out of field cannot have a fielder';
  end if;

  if new.dismissal_type = 'caught_and_bowled'
    and new.fielder_season_roster_id is distinct from new.bowler_season_roster_id then
    raise exception 'caught and bowled must be credited to the bowler';
  end if;

  return new;
end;
$$;

do $migration$
declare
  function_definition text;
  old_fragment constant text := 'and md.dismissal_type in (''bowled'', ''caught'', ''stumped'', ''hit_wicket'', ''hit_out_of_field'')';
  new_fragment constant text := 'and md.dismissal_type in (''bowled'', ''caught'', ''caught_and_bowled'', ''stumped'', ''hit_wicket'', ''hit_out_of_field'')';
begin
  select pg_get_functiondef('public.finalize_match(uuid,uuid)'::regprocedure)
  into function_definition;

  if position(new_fragment in function_definition) > 0 then
    return;
  end if;

  if position(old_fragment in function_definition) = 0 then
    raise exception 'finalize_match wicket calculation could not be updated safely';
  end if;

  execute replace(function_definition, old_fragment, new_fragment);
end;
$migration$;

comment on function public.validate_match_dismissal_type() is
  'Validates supported dismissals, including caught-and-bowled credited to the bowler.';

commit;

