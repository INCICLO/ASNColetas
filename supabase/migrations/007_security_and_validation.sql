-- Segurança, validação e consistência operacional.
-- Execute este arquivo no SQL Editor do Supabase após as migrações anteriores.

create or replace function public.is_active_team_member(required_role public.user_role default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and active
      and (required_role is null or role = required_role)
  );
$$;

revoke all on function public.is_active_team_member(public.user_role) from public;
grant execute on function public.is_active_team_member(public.user_role) to authenticated;

create or replace function public.make_protocol()
returns text
language sql
volatile
set search_path = public
as $$
  select 'SOL-' || extract(year from now())::int || '-'
    || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 12));
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
  clean_name text := trim(coalesce(payload->>'requester_name',''));
  clean_phone text := trim(coalesce(payload->>'phone',''));
  clean_email text := lower(trim(coalesce(payload->>'email','')));
  clean_place_type text := trim(coalesce(payload->>'place_type',''));
  clean_place_name text := nullif(trim(coalesce(payload->>'place_name','')), '');
  clean_cnpj text := nullif(trim(coalesce(payload->>'cnpj','')), '');
  clean_materials text[];
begin
  clean_materials := array(select trim(value) from jsonb_array_elements_text(coalesce(payload->'materials','[]'::jsonb)) value where trim(value) <> '');

  if clean_name !~ '^\\S+\\s+\\S+' then raise exception 'Informe o nome completo.'; end if;
  if clean_phone !~ '^\\+55 [0-9]{2} [0-9]{5}-[0-9]{4}$' then raise exception 'Telefone inválido.'; end if;
  if clean_email !~ '^[^[:space:]@]+@[^[:space:]@]+\\.[^[:space:]@]+$' then raise exception 'E-mail inválido.'; end if;
  if clean_place_type = '' then raise exception 'Informe o tipo do local.'; end if;
  if clean_place_type <> 'Residência' and clean_place_name is null then raise exception 'Informe o nome do local.'; end if;
  if trim(coalesce(payload->>'address','')) = '' or trim(coalesce(payload->>'number','')) = ''
    or trim(coalesce(payload->>'neighborhood','')) = '' or coalesce(payload->>'cep','') !~ '^[0-9]{5}-[0-9]{3}$'
    then raise exception 'Endereço incompleto ou CEP inválido.'; end if;
  if coalesce(array_length(clean_materials,1),0) = 0 then raise exception 'Selecione ao menos um material.'; end if;
  if (payload->>'quantity')::numeric <= 0 then raise exception 'A quantidade deve ser maior que zero.'; end if;
  if length(coalesce(payload->>'notes','')) > 1000 then raise exception 'Observações excedem 1000 caracteres.'; end if;

  -- Barreira de abuso e de duplo clique: uma solicitação idêntica por contato a cada 2 minutos.
  if exists(
    select 1 from public.collection_requests
    where created_at > now() - interval '2 minutes'
      and email = clean_email and phone = clean_phone
  ) then raise exception 'Aguarde dois minutos antes de enviar outra solicitação.'; end if;

  for attempt in 1..5 loop
    new_protocol := public.make_protocol();
    begin
      insert into public.collection_requests(
        protocol,requester_name,phone,email,place_type,place_name,cnpj,address,number,
        neighborhood,cep,latitude,longitude,road_condition,materials,quantity,unit,
        frequency,schedule_preference,notes
      ) values (
        new_protocol,clean_name,clean_phone,clean_email,clean_place_type,clean_place_name,clean_cnpj,
        trim(payload->>'address'),trim(payload->>'number'),trim(payload->>'neighborhood'),payload->>'cep',
        (payload->>'latitude')::double precision,(payload->>'longitude')::double precision,
        (payload->>'road_condition')::smallint,clean_materials,(payload->>'quantity')::numeric,
        payload->>'unit',payload->>'frequency',payload->>'schedule_preference',trim(coalesce(payload->>'notes',''))
      ) returning id into new_id;
      exit;
    exception when unique_violation then
      if attempt = 5 then raise; end if;
    end;
  end loop;

  insert into public.request_events(request_id,event_type,description,actor_name)
  values(new_id,'CRIADA','Solicitação enviada para análise.','Solicitante');
  return new_protocol;
end;
$$;

revoke all on function public.submit_collection_request(jsonb) from public;
grant execute on function public.submit_collection_request(jsonb) to anon,authenticated;

-- Permissões passam a depender do perfil ativo, não de um e-mail fixo.
drop policy if exists "team reads requests" on public.collection_requests;
drop policy if exists "manager reads requests" on public.collection_requests;
drop policy if exists "managers update requests" on public.collection_requests;
drop policy if exists "manager updates requests" on public.collection_requests;
create policy "active team reads requests" on public.collection_requests for select to authenticated
using(public.is_active_team_member());
create policy "active managers update requests" on public.collection_requests for update to authenticated
using(public.is_active_team_member('manager')) with check(public.is_active_team_member('manager'));

-- Uma parada finalizada não pode ser sobrescrita nem gerar eventos duplicados.
create or replace function public.update_driver_stop(p_stop_id uuid,p_completed boolean,p_failure_reason text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  driver_role public.user_role; selected_request uuid; selected_route uuid;
  route_code text; vehicle_category text; current_stop_status text;
begin
  select role into driver_role from public.profiles where id=auth.uid() and active;
  select s.request_id,s.route_id,r.code,v.category,s.status
    into selected_request,selected_route,route_code,vehicle_category,current_stop_status
  from public.route_stops s join public.routes r on r.id=s.route_id
  join public.vehicles v on v.id=r.vehicle_id where s.id=p_stop_id;
  if selected_request is null or not ((driver_role='driver_truck' and vehicle_category='CAMINHÃO') or (driver_role='driver_tricycle' and vehicle_category='TRICICLO'))
    then raise exception 'Parada não autorizada para este motorista.'; end if;
  if current_stop_status <> 'PENDENTE' then raise exception 'Esta parada já foi finalizada.'; end if;
  if not p_completed and nullif(trim(coalesce(p_failure_reason,'')),'') is null then raise exception 'Informe o motivo da coleta não realizada.'; end if;

  update public.route_stops set status=case when p_completed then 'COLETADA' else 'NÃO COLETADA' end,
    arrived_at=coalesce(arrived_at,now()),completed_at=now(),failure_reason=case when p_completed then null else trim(p_failure_reason) end
  where id=p_stop_id and status='PENDENTE';
  update public.collection_requests set status=case when p_completed then 'COLETADA'::public.request_status else 'NÃO COLETADA'::public.request_status end,
    collected_at=case when p_completed then now() else null end,updated_at=now() where id=selected_request;
  update public.routes set status='EM ROTA' where id=selected_route and status='PLANEJADA';
  if not exists(select 1 from public.route_stops where route_id=selected_route and status='PENDENTE') then update public.routes set status='FINALIZADA' where id=selected_route; end if;
  insert into public.request_events(request_id,event_type,description,actor_id,actor_name)
  values(selected_request,case when p_completed then 'COLETADA' else 'NÃO COLETADA' end,
    case when p_completed then 'Coleta realizada na rota '||route_code||'.' else 'Coleta não realizada na rota '||route_code||': '||trim(p_failure_reason) end,
    auth.uid(),coalesce((select full_name from public.profiles where id=auth.uid()),'Motorista'));
  return case when p_completed then 'COLETADA' else 'NÃO COLETADA' end;
end;
$$;

revoke all on function public.update_driver_stop(uuid,boolean,text) from public;
grant execute on function public.update_driver_stop(uuid,boolean,text) to authenticated;
