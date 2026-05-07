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

drop function if exists public.cleanup_unused_multiplayer_rooms(integer, integer);
create or replace function public.cleanup_unused_multiplayer_rooms(
	p_closed_hours integer default 24,
	p_stale_open_minutes integer default 45
)
returns table(closed_deleted bigint, stale_open_deleted bigint, total_deleted bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
	v_closed_deleted bigint := 0;
	v_stale_open_deleted bigint := 0;
begin
	with deleted_closed as (
		delete from public.multiplayer_rooms
		where status = 'closed'
			and updated_at < timezone('utc', now()) - make_interval(hours => greatest(p_closed_hours, 1))
		returning room_code
	)
	select count(*) into v_closed_deleted from deleted_closed;

	with deleted_open as (
		delete from public.multiplayer_rooms
		where status = 'open'
			and updated_at < timezone('utc', now()) - make_interval(mins => greatest(p_stale_open_minutes, 5))
		returning room_code
	)
	select count(*) into v_stale_open_deleted from deleted_open;

	return query
	select
		v_closed_deleted,
		v_stale_open_deleted,
		v_closed_deleted + v_stale_open_deleted;
end;
$$;

revoke all on function public.cleanup_unused_multiplayer_rooms(integer, integer) from public;
grant execute on function public.cleanup_unused_multiplayer_rooms(integer, integer) to service_role;
