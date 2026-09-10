-- Reparo idempotente do fluxo público de solicitações e da leitura pelo gestor.
-- Execute todo este arquivo no SQL Editor do projeto Supabase.

create or replace function public.make_protocol()
returns text
language sql
volatile
set search_path = public
as $$
  select 'SOL-'
    || extract(year from now())::int
    || '-'
    || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
$$;

create or replace function public.submit_collection_request(payload jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  new_protocol text;
  attempt smallint;
begin
  for attempt in 1..5 loop
    new_protocol := public.make_protocol();
    begin
      insert into public.collection_requests(
        protocol, requester_name, phone, email, place_type, place_name, cnpj,
        address, number, neighborhood, cep, latitude, longitude, road_condition,
        materials, quantity, unit, frequency, schedule_preference, notes
      ) values (
        new_protocol,
        nullif(trim(payload->>'requester_name'), ''),
        payload->>'phone',
        lower(trim(payload->>'email')),
        payload->>'place_type',
        nullif(trim(payload->>'place_name'), ''),
        nullif(trim(payload->>'cnpj'), ''),
        payload->>'address',
        payload->>'number',
        payload->>'neighborhood',
        payload->>'cep',
        (payload->>'latitude')::double precision,
        (payload->>'longitude')::double precision,
        (payload->>'road_condition')::smallint,
        array(select jsonb_array_elements_text(payload->'materials')),
        (payload->>'quantity')::numeric,
        payload->>'unit',
        payload->>'frequency',
        payload->>'schedule_preference',
        coalesce(payload->>'notes', '')
      ) returning id into new_id;
      exit;
    exception when unique_violation then
      if attempt = 5 then raise; end if;
    end;
  end loop;

  insert into public.request_events(request_id, event_type, description, actor_name)
  values(new_id, 'CRIADA', 'Solicitação enviada para análise.', 'Solicitante');

  return new_protocol;
end;
$$;

revoke all on function public.submit_collection_request(jsonb) from public;
grant execute on function public.submit_collection_request(jsonb) to anon, authenticated;
grant execute on function public.track_collection_request(text) to anon, authenticated;

-- Garante que o login principal esteja autorizado pelas políticas RLS da equipe.
insert into public.profiles(id, full_name, role, active)
select id, coalesce(nullif(raw_user_meta_data->>'full_name', ''), 'Gestor ASN'), 'manager', true
from auth.users
where lower(email) = 'recicle.trairi@gmail.com'
on conflict(id) do update
set full_name = excluded.full_name,
    role = 'manager',
    active = true;

alter table public.collection_requests enable row level security;
alter table public.request_events enable row level security;

drop policy if exists "team reads requests" on public.collection_requests;
create policy "team reads requests"
on public.collection_requests for select to authenticated
using(exists(
  select 1 from public.profiles p
  where p.id = auth.uid() and p.active
));

drop policy if exists "managers update requests" on public.collection_requests;
create policy "managers update requests"
on public.collection_requests for update to authenticated
using(exists(
  select 1 from public.profiles p
  where p.id = auth.uid() and p.role = 'manager' and p.active
))
with check(exists(
  select 1 from public.profiles p
  where p.id = auth.uid() and p.role = 'manager' and p.active
));

-- Ativa a atualização instantânea do painel sem falhar se a tabela já estiver publicada.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'collection_requests'
  ) then
    alter publication supabase_realtime add table public.collection_requests;
  end if;
end $$;

-- Teste final: deve retornar um código como SOL-2026-A1B2C3.
select public.make_protocol() as teste_protocolo;
