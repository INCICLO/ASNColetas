-- Cria rotas persistentes com até 10 paradas. Execute no SQL Editor do Supabase.

create or replace function public.create_collection_route(
  p_vehicle_name text,
  p_collection_date date,
  p_request_ids uuid[],
  p_distance_km numeric,
  p_estimated_fuel_liters numeric
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_route_id uuid;
  new_code text;
  selected_vehicle_id uuid;
begin
  if lower(coalesce(auth.jwt()->>'email', '')) <> 'recicle.trairi@gmail.com' then
    raise exception 'Apenas o gestor autorizado pode gerar rotas.';
  end if;
  if p_collection_date is null or p_collection_date < current_date then
    raise exception 'Informe uma data de coleta válida.';
  end if;
  if not (coalesce(array_length(p_request_ids, 1), 0) between 1 and 10) then
    raise exception 'A rota precisa ter entre 1 e 10 paradas.';
  end if;
  if exists (
    select 1 from unnest(p_request_ids) request_id
    left join public.collection_requests r on r.id = request_id
    where r.id is null or r.status <> 'APROVADA'
  ) then
    raise exception 'Todas as solicitações precisam estar aprovadas.';
  end if;

  select id into selected_vehicle_id
  from public.vehicles
  where name = p_vehicle_name and active
  limit 1;
  if selected_vehicle_id is null then raise exception 'Veículo indisponível.'; end if;

  new_code := 'ROT-' || extract(year from p_collection_date)::int || '-'
    || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  insert into public.routes(
    code, vehicle_id, collection_date, status, distance_km,
    estimated_fuel_liters, created_by
  ) values (
    new_code, selected_vehicle_id, p_collection_date, 'PLANEJADA',
    greatest(coalesce(p_distance_km, 0), 0),
    greatest(coalesce(p_estimated_fuel_liters, 0), 0), auth.uid()
  ) returning id into new_route_id;

  insert into public.route_stops(route_id, request_id, stop_order)
  select new_route_id, request_id, position::smallint
  from unnest(p_request_ids) with ordinality as stops(request_id, position);

  update public.collection_requests
  set status = 'AGENDADA', vehicle = p_vehicle_name, updated_at = now()
  where id = any(p_request_ids);

  insert into public.request_events(request_id, event_type, description, actor_id, actor_name)
  select request_id, 'AGENDADA', 'Solicitação incluída na rota ' || new_code || '.', auth.uid(), 'Gestor ASN'
  from unnest(p_request_ids) request_id;

  return new_code;
end;
$$;

revoke all on function public.create_collection_route(text,date,uuid[],numeric,numeric) from public;
grant execute on function public.create_collection_route(text,date,uuid[],numeric,numeric) to authenticated;

drop policy if exists "manager reads routes" on public.routes;
create policy "manager reads routes" on public.routes for select to authenticated
using(lower(coalesce(auth.jwt()->>'email','')) = 'recicle.trairi@gmail.com');

drop policy if exists "manager reads stops" on public.route_stops;
create policy "manager reads stops" on public.route_stops for select to authenticated
using(lower(coalesce(auth.jwt()->>'email','')) = 'recicle.trairi@gmail.com');

grant select on public.routes, public.route_stops, public.vehicles to authenticated;
