-- Corrige a leitura e a análise de solicitações pelo gestor principal.
-- O acesso fica restrito ao e-mail administrativo informado pela Associação.

alter table public.collection_requests enable row level security;

drop policy if exists "team reads requests" on public.collection_requests;
drop policy if exists "manager reads requests" on public.collection_requests;
create policy "manager reads requests"
on public.collection_requests
for select
to authenticated
using (
  lower(coalesce(auth.jwt()->>'email', '')) = 'recicle.trairi@gmail.com'
);

drop policy if exists "managers update requests" on public.collection_requests;
drop policy if exists "manager updates requests" on public.collection_requests;
create policy "manager updates requests"
on public.collection_requests
for update
to authenticated
using (
  lower(coalesce(auth.jwt()->>'email', '')) = 'recicle.trairi@gmail.com'
)
with check (
  lower(coalesce(auth.jwt()->>'email', '')) = 'recicle.trairi@gmail.com'
);

-- Mantém o cadastro administrativo sincronizado, sem ampliar o acesso.
insert into public.profiles(id, full_name, role, active)
select
  id,
  coalesce(nullif(raw_user_meta_data->>'full_name', ''), 'Gestor ASN'),
  'manager',
  true
from auth.users
where lower(email) = 'recicle.trairi@gmail.com'
on conflict(id) do update
set full_name = excluded.full_name,
    role = 'manager',
    active = true;

-- Diagnóstico: solicitacoes_salvas deve ser maior que zero e o perfil deve ser manager.
select
  u.email,
  p.full_name,
  p.role,
  p.active,
  (select count(*) from public.collection_requests) as solicitacoes_salvas
from auth.users u
left join public.profiles p on p.id = u.id
where lower(u.email) = 'recicle.trairi@gmail.com';
