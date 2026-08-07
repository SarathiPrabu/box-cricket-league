alter table public.league_members
  drop constraint if exists league_members_league_user_unique,
  add constraint league_members_league_user_role_unique unique (league_id, user_id, role);

create or replace function public.get_league_role_assignments(
  target_league_slug text default 'box-cricket-league'
)
returns table (
  user_id uuid,
  email text,
  display_name text,
  role text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    au.id as user_id,
    au.email,
    coalesce(
      nullif(au.raw_user_meta_data ->> 'name', ''),
      nullif(au.raw_user_meta_data ->> 'full_name', ''),
      au.email
    ) as display_name,
    lm.role
  from auth.users au
  cross join public.leagues l
  left join public.league_members lm
    on lm.league_id = l.id
   and lm.user_id = au.id
  where l.slug = target_league_slug
    and public.has_league_role(l.id, array['admin'])
  order by display_name, au.email, lm.role;
$$;

create or replace function public.set_league_member_roles(
  target_league_slug text,
  target_user_id uuid,
  target_roles text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_league_id uuid;
begin
  select id into target_league_id
  from public.leagues
  where slug = target_league_slug;

  if target_league_id is null then
    raise exception 'league not found';
  end if;

  if not public.has_league_role(target_league_id, array['admin']) then
    raise exception 'only league admins can assign roles';
  end if;

  if target_user_id = auth.uid()
    and not ('admin' = any(coalesce(target_roles, array[]::text[]))) then
    raise exception 'admins cannot remove their own admin role';
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_roles, array[]::text[])) as requested_role
    where requested_role not in ('admin', 'scorer', 'player', 'team_manager')
  ) then
    raise exception 'invalid league role';
  end if;

  delete from public.league_members
  where league_id = target_league_id
    and user_id = target_user_id;

  insert into public.league_members (league_id, user_id, role)
  select target_league_id, target_user_id, requested_role
  from unnest(coalesce(target_roles, array[]::text[])) as requested_role;
end;
$$;

grant execute on function public.set_league_member_roles(text, uuid, text[]) to authenticated;
