-- Replace run out with the league-specific hit out of field dismissal.
-- Historical run-out rows remain readable, but new or changed rows cannot use it.

alter table public.match_deliveries
  drop constraint if exists match_deliveries_dismissal_type_check;

alter table public.match_deliveries
  add constraint match_deliveries_dismissal_type_check check (
    dismissal_type is null
    or dismissal_type in ('bowled', 'caught', 'stumped', 'hit_wicket', 'hit_out_of_field')
  ) not valid;

do $$
begin
  if not exists (
    select 1
    from public.match_deliveries
    where dismissal_type = 'run_out'
  ) then
    alter table public.match_deliveries
      validate constraint match_deliveries_dismissal_type_check;
  end if;
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

  return new;
end;
$$;

drop trigger if exists match_deliveries_validate_dismissal_type
  on public.match_deliveries;

create trigger match_deliveries_validate_dismissal_type
before insert or update on public.match_deliveries
for each row execute function public.validate_match_dismissal_type();

-- Preserve the deployed finalize_match implementation, including its access
-- checks, and change only the bowler-wicket dismissal list.
do $migration$
declare
  function_definition text;
  old_fragment constant text := 'and md.dismissal_type in (''bowled'', ''caught'', ''stumped'', ''hit_wicket'')';
  new_fragment constant text := 'and md.dismissal_type in (''bowled'', ''caught'', ''stumped'', ''hit_wicket'', ''hit_out_of_field'')';
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
  'Rejects retired run-out dismissals and fielders on hit-out-of-field wickets.';
