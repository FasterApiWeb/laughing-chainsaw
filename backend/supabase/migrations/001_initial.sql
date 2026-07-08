-- LibreRing initial schema (Supabase Postgres)
-- Run: supabase db push  OR apply via Supabase dashboard SQL editor

-- ---------------------------------------------------------------------------
-- Profiles (extends auth.users)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Registered devices (rings)
-- ---------------------------------------------------------------------------
create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null default 'Oura Ring',
  ble_mac text,
  firmware_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, ble_mac)
);

alter table public.devices enable row level security;

create policy "devices_all_own"
  on public.devices for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Sync cursors (per user + device)
-- ---------------------------------------------------------------------------
create table if not exists public.sync_cursors (
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid not null references public.devices (id) on delete cascade,
  cursor text not null default '0',
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.sync_cursors enable row level security;

create policy "sync_cursors_all_own"
  on public.sync_cursors for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Time-series tables (mirror local SQLite / IndexedDB schema)
-- ---------------------------------------------------------------------------
create table if not exists public.heart_rate (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  timestamp double precision not null,
  bpm double precision not null,
  ibi_ms integer,
  unique (user_id, timestamp)
);

create table if not exists public.spo2 (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  timestamp double precision not null,
  percent integer not null,
  unique (user_id, timestamp)
);

create table if not exists public.temperature (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  timestamp double precision not null,
  celsius double precision not null,
  unique (user_id, timestamp)
);

create table if not exists public.sleep_phase (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  timestamp double precision not null,
  phase smallint not null,
  unique (user_id, timestamp)
);

create table if not exists public.steps (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid references public.devices (id) on delete set null,
  timestamp double precision not null,
  count integer not null,
  unique (user_id, timestamp)
);

create table if not exists public.daily_summary (
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  total_steps integer default 0,
  avg_hr double precision default 0,
  min_hr double precision default 0,
  avg_hrv double precision default 0,
  avg_spo2 double precision default 0,
  avg_temp double precision default 0,
  sleep_score integer default 0,
  readiness_score integer default 0,
  activity_score integer default 0,
  primary key (user_id, date)
);

create table if not exists public.baselines (
  user_id uuid not null references auth.users (id) on delete cascade,
  metric text not null,
  mean double precision not null,
  deviation double precision not null,
  sample_count integer not null,
  last_updated double precision not null,
  primary key (user_id, metric)
);

create table if not exists public.imports (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  filename text not null,
  source text not null,
  imported_at timestamptz not null default now(),
  record_count integer not null default 0,
  hash text not null,
  unique (user_id, hash)
);

-- RLS for all metric tables
do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'heart_rate', 'spo2', 'temperature', 'sleep_phase', 'steps',
    'daily_summary', 'baselines', 'imports'
  ] loop
    execute format('alter table public.%I enable row level security', tbl);
    execute format(
      'create policy %I on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      tbl || '_all_own', tbl
    );
  end loop;
end $$;

create index if not exists idx_hr_user_ts on public.heart_rate (user_id, timestamp);
create index if not exists idx_spo2_user_ts on public.spo2 (user_id, timestamp);

-- ---------------------------------------------------------------------------
-- Blob metadata (files live in Cloudflare R2)
-- ---------------------------------------------------------------------------
create table if not exists public.storage_objects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  object_key text not null,
  filename text not null,
  content_type text not null,
  byte_size bigint,
  created_at timestamptz not null default now(),
  unique (user_id, object_key)
);

alter table public.storage_objects enable row level security;

create policy "storage_objects_all_own"
  on public.storage_objects for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- RPC: push_sync_batch
-- ---------------------------------------------------------------------------
create or replace function public.push_sync_batch(
  p_device_id uuid,
  p_cursor text,
  p_batches jsonb
)
returns jsonb
language plpgsql
security invoker
as $$
declare
  v_user uuid := auth.uid();
  v_batch jsonb;
  v_table text;
  v_records jsonb;
  v_rec jsonb;
  v_inserted int := 0;
  v_skipped int := 0;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  for v_batch in select * from jsonb_array_elements(p_batches)
  loop
    v_table := v_batch->>'table';
    v_records := v_batch->'records';

    if v_table = 'heart_rate' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.heart_rate (user_id, device_id, timestamp, bpm, ibi_ms)
          values (
            v_user, p_device_id,
            (v_rec->>'timestamp')::double precision,
            (v_rec->>'bpm')::double precision,
            nullif(v_rec->>'ibi_ms', '')::integer
          );
          v_inserted := v_inserted + 1;
        exception when unique_violation then
          v_skipped := v_skipped + 1;
        end;
      end loop;
    end if;
    -- Additional tables: extend in migration 002 or client-side per-table upsert
  end loop;

  insert into public.sync_cursors (user_id, device_id, cursor, updated_at)
  values (v_user, p_device_id, p_cursor, now())
  on conflict (user_id, device_id)
  do update set cursor = excluded.cursor, updated_at = now();

  return jsonb_build_object(
    'new_cursor', p_cursor,
    'inserted', v_inserted,
    'skipped', v_skipped
  );
end;
$$;

grant execute on function public.push_sync_batch(uuid, text, jsonb) to authenticated;
