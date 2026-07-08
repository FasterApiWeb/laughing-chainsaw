-- Fix RLS: auto-set user_id on insert when client omits it.
-- Run in Supabase SQL Editor if sync fails with "row-level security policy" on devices.

create or replace function public.set_owner_user_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is null then
    new.user_id := auth.uid();
  end if;
  if new.user_id is distinct from auth.uid() then
    raise exception 'forbidden';
  end if;
  return new;
end;
$$;

drop trigger if exists devices_set_user_id on public.devices;
create trigger devices_set_user_id
  before insert on public.devices
  for each row execute function public.set_owner_user_id();

drop trigger if exists storage_objects_set_user_id on public.storage_objects;
create trigger storage_objects_set_user_id
  before insert on public.storage_objects
  for each row execute function public.set_owner_user_id();

-- Allow selecting own devices (explicit select policy if needed)
drop policy if exists "devices_select_own" on public.devices;
create policy "devices_select_own"
  on public.devices for select
  using (auth.uid() = user_id);

drop policy if exists "devices_insert_own" on public.devices;
create policy "devices_insert_own"
  on public.devices for insert
  with check (auth.uid() = user_id);

drop policy if exists "devices_update_own" on public.devices;
create policy "devices_update_own"
  on public.devices for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "devices_delete_own" on public.devices;
create policy "devices_delete_own"
  on public.devices for delete
  using (auth.uid() = user_id);

-- Replace catch-all policy from 001
drop policy if exists "devices_all_own" on public.devices;
