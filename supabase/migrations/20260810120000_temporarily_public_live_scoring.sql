-- Temporary review mode: the live scorer is public until role protection is re-enabled.

do $$
declare
  function_signature regprocedure;
  function_definition text;
begin
  foreach function_signature in array array[
    'public.start_match(uuid, uuid)'::regprocedure,
    'public.set_match_over_assignment(uuid, integer, uuid, uuid, uuid)'::regprocedure,
    'public.record_match_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid)'::regprocedure,
    'public.update_current_over_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid)'::regprocedure,
    'public.delete_current_over_delivery(uuid)'::regprocedure,
    'public.complete_match_innings(uuid)'::regprocedure,
    'public.finalize_match(uuid, uuid)'::regprocedure,
    'public.mark_match_no_result(uuid)'::regprocedure,
    'public.get_match_scoring_state(uuid)'::regprocedure
  ] loop
    select pg_get_functiondef(function_signature::oid)
    into function_definition;

    function_definition := regexp_replace(
      function_definition,
      E'\n  if not public\.has_league_role\(.*?\n  end if;\n',
      E'\n',
      1,
      1,
      's'
    );

    execute function_definition;
  end loop;
end;
$$;

alter table public.match_deliveries
  drop constraint if exists match_deliveries_no_ball_batter_runs_check,
  add constraint match_deliveries_no_ball_batter_runs_check check (
    delivery_type <> 'no_ball'
    or batter_runs in (0, 1, 2, 4, 6)
  );

grant execute on function public.start_match(uuid, uuid) to anon, authenticated;
grant execute on function public.set_match_over_assignment(uuid, integer, uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.record_match_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.update_current_over_delivery(uuid, uuid, uuid, text, integer, integer, boolean, uuid, text, uuid) to anon, authenticated;
grant execute on function public.delete_current_over_delivery(uuid) to anon, authenticated;
grant execute on function public.complete_match_innings(uuid) to anon, authenticated;
grant execute on function public.finalize_match(uuid, uuid) to anon, authenticated;
grant execute on function public.mark_match_no_result(uuid) to anon, authenticated;
grant execute on function public.get_match_scoring_state(uuid) to anon, authenticated;

grant select on public.matches, public.match_innings, public.match_over_assignments, public.match_deliveries to anon;

drop policy if exists "public can read matches for live scoring" on public.matches;
create policy "public can read matches for live scoring"
on public.matches
for select
using (true);

drop policy if exists "public can read match innings for live scoring" on public.match_innings;
create policy "public can read match innings for live scoring"
on public.match_innings
for select
using (true);

drop policy if exists "public can read match overs for live scoring" on public.match_over_assignments;
create policy "public can read match overs for live scoring"
on public.match_over_assignments
for select
using (true);

drop policy if exists "public can read match deliveries for live scoring" on public.match_deliveries;
create policy "public can read match deliveries for live scoring"
on public.match_deliveries
for select
using (true);
