create table if not exists public.multiplayer_rooms (
	room_code text primary key,
	session_id text not null,
	status text not null default 'open',
	transport_type text not null default 'direct_enet',
	host_address text not null,
	host_port integer not null,
	created_at timestamptz not null default timezone('utc', now()),
	updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists multiplayer_rooms_status_idx
	on public.multiplayer_rooms (status, created_at desc);

create or replace function public.set_multiplayer_room_updated_at()
returns trigger
language plpgsql
as $$
begin
	new.updated_at = timezone('utc', now());
	return new;
end;
$$;

drop trigger if exists multiplayer_rooms_set_updated_at on public.multiplayer_rooms;
create trigger multiplayer_rooms_set_updated_at
before update on public.multiplayer_rooms
for each row
execute function public.set_multiplayer_room_updated_at();

alter table public.multiplayer_rooms enable row level security;

drop policy if exists "anon can create multiplayer rooms" on public.multiplayer_rooms;
create policy "anon can create multiplayer rooms"
on public.multiplayer_rooms
for insert
to anon
with check (true);

drop policy if exists "anon can read open multiplayer rooms" on public.multiplayer_rooms;
create policy "anon can read open multiplayer rooms"
on public.multiplayer_rooms
for select
to anon
using (status = 'open');

drop policy if exists "anon can close multiplayer rooms" on public.multiplayer_rooms;
create policy "anon can close multiplayer rooms"
on public.multiplayer_rooms
for update
to anon
using (true)
with check (true);
