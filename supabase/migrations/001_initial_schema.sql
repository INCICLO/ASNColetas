create extension if not exists pgcrypto;

create type public.user_role as enum ('manager','driver_truck','driver_tricycle');
create type public.request_status as enum ('NOVA','EM ANÁLISE','APROVADA','RECUSADA','AGENDADA','EM ROTA','COLETADA','NÃO COLETADA','FINALIZADA');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.user_role not null default 'manager',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.collection_requests (
  id uuid primary key default gen_random_uuid(),
  protocol text not null unique,
  requester_name text not null,
  phone text not null check (phone ~ '^\+55 [0-9]{2} [0-9]{5}-[0-9]{4}$'),
  email text not null,
  place_type text not null,
  place_name text,
  cnpj text,
  address text not null,
  number text not null,
  neighborhood text not null,
  cep text not null,
  latitude double precision not null,
  longitude double precision not null,
  road_condition smallint not null check (road_condition between 1 and 5),
  materials text[] not null,
  quantity numeric(12,2) not null check (quantity > 0),
  unit text not null,
  frequency text not null,
  schedule_preference text not null,
  notes text not null default '',
  status public.request_status not null default 'NOVA',
  decision_reason text,
  vehicle text,
  preferred_collection_date date,
  collected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.request_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.collection_requests(id) on delete cascade,
  event_type text not null,
  description text not null,
  actor_id uuid references auth.users(id),
  actor_name text not null default 'Sistema',
  created_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(), name text not null, category text not null,
  plate text, fuel_type text not null default 'Diesel', average_km_per_l numeric(8,2) not null,
  capacity_liters numeric(12,2), active boolean not null default true, created_at timestamptz not null default now()
);

create table public.routes (
  id uuid primary key default gen_random_uuid(), code text not null unique, vehicle_id uuid not null references public.vehicles(id),
  driver_id uuid references public.profiles(id), collection_date date not null, status text not null default 'PLANEJADA',
  distance_km numeric(10,2) not null default 0, estimated_fuel_liters numeric(10,2) not null default 0,
  created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);

create table public.route_stops (
  id uuid primary key default gen_random_uuid(), route_id uuid not null references public.routes(id) on delete cascade,
  request_id uuid not null references public.collection_requests(id), stop_order smallint not null check(stop_order between 1 and 10),
  status text not null default 'PENDENTE', arrived_at timestamptz, completed_at timestamptz, failure_reason text,
  unique(route_id, stop_order), unique(route_id, request_id)
);

create index idx_requests_status_created on public.collection_requests(status,created_at);
create index idx_requests_neighborhood on public.collection_requests(neighborhood);
create index idx_events_request_created on public.request_events(request_id,created_at desc);
create index idx_routes_date_vehicle on public.routes(collection_date,vehicle_id);

create or replace function public.make_protocol() returns text language sql as $$
  select 'SOL-'||extract(year from now())::int||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
$$;

create or replace function public.submit_collection_request(payload jsonb) returns text
language plpgsql security definer set search_path=public as $$
declare new_id uuid; new_protocol text:=public.make_protocol();
begin
  insert into public.collection_requests(protocol,requester_name,phone,email,place_type,place_name,cnpj,address,number,neighborhood,cep,latitude,longitude,road_condition,materials,quantity,unit,frequency,schedule_preference,notes)
  values(new_protocol,payload->>'requester_name',payload->>'phone',lower(payload->>'email'),payload->>'place_type',payload->>'place_name',payload->>'cnpj',payload->>'address',payload->>'number',payload->>'neighborhood',payload->>'cep',(payload->>'latitude')::float8,(payload->>'longitude')::float8,(payload->>'road_condition')::smallint,array(select jsonb_array_elements_text(payload->'materials')),(payload->>'quantity')::numeric,payload->>'unit',payload->>'frequency',payload->>'schedule_preference',coalesce(payload->>'notes','')) returning id into new_id;
  insert into public.request_events(request_id,event_type,description,actor_name) values(new_id,'CRIADA','Solicitação enviada para análise.','Solicitante');
  return new_protocol;
end $$;

create or replace function public.track_collection_request(p_protocol text)
returns table(id uuid,protocol text,requester_name text,place_type text,address text,neighborhood text,materials text[],quantity numeric,unit text,frequency text,status public.request_status,vehicle text,created_at timestamptz,latitude float8,longitude float8)
language sql security definer set search_path=public as $$
 select r.id,r.protocol,r.requester_name,r.place_type,r.address,r.neighborhood,r.materials,r.quantity,r.unit,r.frequency,r.status,r.vehicle,r.created_at,r.latitude,r.longitude from public.collection_requests r where r.protocol=upper(trim(p_protocol)) limit 1;
$$;

grant execute on function public.submit_collection_request(jsonb) to anon,authenticated;
grant execute on function public.track_collection_request(text) to anon,authenticated;

alter table public.profiles enable row level security; alter table public.collection_requests enable row level security;
alter table public.request_events enable row level security; alter table public.vehicles enable row level security;
alter table public.routes enable row level security; alter table public.route_stops enable row level security;

create policy "team reads requests" on public.collection_requests for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.active));
create policy "managers update requests" on public.collection_requests for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager' and p.active));
create policy "team reads events" on public.request_events for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.active));
create policy "team creates events" on public.request_events for insert to authenticated with check(exists(select 1 from public.profiles p where p.id=auth.uid() and p.active));
create policy "team reads vehicles" on public.vehicles for select to authenticated using(true);
create policy "team reads routes" on public.routes for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.active));
create policy "managers manage routes" on public.routes for all to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='manager'));
create policy "team reads stops" on public.route_stops for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.active));
create policy "team updates stops" on public.route_stops for update to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.active));

insert into public.vehicles(name,category,plate,fuel_type,average_km_per_l,capacity_liters) values
('M.BENZ/ACCELO 817','CAMINHÃO',null,'Diesel',7.5,30000),('Triciclo com gaiola','TRICICLO',null,'Gasolina',28,1000);
