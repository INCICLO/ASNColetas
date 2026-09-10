-- Operação móvel dos motoristas. Execute no SQL Editor do Supabase.

create or replace function public.get_my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role::text from public.profiles where id = auth.uid() and active limit 1;
$$;

create or replace function public.get_driver_stops()
returns table(
  route_id uuid, route_code text, collection_date date, route_status text,
  vehicle_name text, stop_id uuid, stop_order smallint, stop_status text,
  request_id uuid, requester_name text, address text, number text,
  neighborhood text, materials text[], quantity numeric, unit text,
  latitude double precision, longitude double precision
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare driver_role public.user_role;
begin
  select role into driver_role from public.profiles where id = auth.uid() and active;
  if driver_role not in ('driver_truck','driver_tricycle') then
    raise exception 'Acesso exclusivo para motoristas.';
  end if;
  return query
  select r.id,r.code,r.collection_date,r.status,v.name,s.id,s.stop_order,s.status,
    q.id,q.requester_name,q.address,q.number,q.neighborhood,q.materials,q.quantity,q.unit,
    q.latitude,q.longitude
  from public.routes r
  join public.vehicles v on v.id=r.vehicle_id
  join public.route_stops s on s.route_id=r.id
  join public.collection_requests q on q.id=s.request_id
  where r.status in ('PLANEJADA','EM ROTA')
    and r.collection_date >= current_date - 1
    and ((driver_role='driver_truck' and v.category='CAMINHÃO')
      or (driver_role='driver_tricycle' and v.category='TRICICLO'))
  order by r.collection_date,r.created_at,s.stop_order;
end;
$$;

create or replace function public.update_driver_stop(
  p_stop_id uuid,
  p_completed boolean,
  p_failure_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  driver_role public.user_role;
  selected_request uuid;
  selected_route uuid;
  route_code text;
  vehicle_category text;
begin
  select role into driver_role from public.profiles where id=auth.uid() and active;
  select s.request_id,s.route_id,r.code,v.category
    into selected_request,selected_route,route_code,vehicle_category
  from public.route_stops s
  join public.routes r on r.id=s.route_id
  join public.vehicles v on v.id=r.vehicle_id
  where s.id=p_stop_id;

  if selected_request is null
    or not ((driver_role='driver_truck' and vehicle_category='CAMINHÃO')
      or (driver_role='driver_tricycle' and vehicle_category='TRICICLO')) then
    raise exception 'Parada não autorizada para este motorista.';
  end if;

  update public.route_stops set
    status=case when p_completed then 'COLETADA' else 'NÃO COLETADA' end,
    arrived_at=coalesce(arrived_at,now()), completed_at=now(),
    failure_reason=case when p_completed then null else nullif(trim(p_failure_reason),'') end
  where id=p_stop_id;

  update public.collection_requests set
    status=case when p_completed then 'COLETADA'::public.request_status else 'NÃO COLETADA'::public.request_status end,
    collected_at=case when p_completed then now() else null end,updated_at=now()
  where id=selected_request;

  update public.routes set status='EM ROTA' where id=selected_route and status='PLANEJADA';
  if not exists(select 1 from public.route_stops where route_id=selected_route and status='PENDENTE') then
    update public.routes set status='FINALIZADA' where id=selected_route;
  end if;

  insert into public.request_events(request_id,event_type,description,actor_id,actor_name)
  values(selected_request,case when p_completed then 'COLETADA' else 'NÃO COLETADA' end,
    case when p_completed then 'Coleta realizada na rota '||route_code||'.'
      else 'Coleta não realizada na rota '||route_code||coalesce(': '||nullif(trim(p_failure_reason),''),'.') end,
    auth.uid(),'Motorista');
  return case when p_completed then 'COLETADA' else 'NÃO COLETADA' end;
end;
$$;

revoke all on function public.get_my_role() from public;
revoke all on function public.get_driver_stops() from public;
revoke all on function public.update_driver_stop(uuid,boolean,text) from public;
grant execute on function public.get_my_role() to authenticated;
grant execute on function public.get_driver_stops() to authenticated;
grant execute on function public.update_driver_stop(uuid,boolean,text) to authenticated;

-- Depois de criar as contas no Authentication > Users, execute novamente este bloco.
insert into public.profiles(id,full_name,role,active)
select id,'Motorista do Caminhão','driver_truck',true from auth.users
where lower(email)='recicle.trairi+caminhao@gmail.com'
on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=true;

insert into public.profiles(id,full_name,role,active)
select id,'Motorista do Triciclo','driver_tricycle',true from auth.users
where lower(email)='recicle.trairi+triciclo@gmail.com'
on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=true;
