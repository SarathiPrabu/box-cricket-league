create or replace function public.get_public_players()
returns table (
  id uuid,
  slug text,
  display_name text,
  full_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.slug, p.display_name, p.full_name
  from public.players p
  order by p.display_name;
$$;

grant execute on function public.get_public_players() to anon, authenticated;
