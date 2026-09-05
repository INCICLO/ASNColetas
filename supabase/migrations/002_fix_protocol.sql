-- Execute esta migração no SQL Editor do Supabase já configurado.
-- Usa gen_random_uuid, que já é usado pelas tabelas deste projeto.
create or replace function public.make_protocol()
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select 'SOL-'
    || extract(year from now())::int
    || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
$$;
