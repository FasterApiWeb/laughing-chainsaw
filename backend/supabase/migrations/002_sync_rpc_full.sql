-- Extend push_sync_batch for all tables + add pull_sync_delta

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

  if not exists (
    select 1 from public.devices d
    where d.id = p_device_id and d.user_id = v_user
  ) then
    raise exception 'device not found';
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
        exception when unique_violation then v_skipped := v_skipped + 1;
        end;
      end loop;

    elsif v_table = 'spo2' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.spo2 (user_id, device_id, timestamp, percent)
          values (
            v_user, p_device_id,
            (v_rec->>'timestamp')::double precision,
            (v_rec->>'percent')::integer
          );
          v_inserted := v_inserted + 1;
        exception when unique_violation then v_skipped := v_skipped + 1;
        end;
      end loop;

    elsif v_table = 'temperature' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.temperature (user_id, device_id, timestamp, celsius)
          values (
            v_user, p_device_id,
            (v_rec->>'timestamp')::double precision,
            (v_rec->>'celsius')::double precision
          );
          v_inserted := v_inserted + 1;
        exception when unique_violation then v_skipped := v_skipped + 1;
        end;
      end loop;

    elsif v_table = 'sleep_phase' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.sleep_phase (user_id, device_id, timestamp, phase)
          values (
            v_user, p_device_id,
            (v_rec->>'timestamp')::double precision,
            (v_rec->>'phase')::smallint
          );
          v_inserted := v_inserted + 1;
        exception when unique_violation then v_skipped := v_skipped + 1;
        end;
      end loop;

    elsif v_table = 'steps' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.steps (user_id, device_id, timestamp, count)
          values (
            v_user, p_device_id,
            (v_rec->>'timestamp')::double precision,
            (v_rec->>'count')::integer
          );
          v_inserted := v_inserted + 1;
        exception when unique_violation then v_skipped := v_skipped + 1;
        end;
      end loop;

    elsif v_table = 'daily_summary' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.daily_summary (
            user_id, date, total_steps, avg_hr, min_hr, avg_hrv,
            avg_spo2, avg_temp, sleep_score, readiness_score, activity_score
          )
          values (
            v_user,
            (v_rec->>'date')::date,
            coalesce((v_rec->>'total_steps')::integer, 0),
            coalesce((v_rec->>'avg_hr')::double precision, 0),
            coalesce((v_rec->>'min_hr')::double precision, 0),
            coalesce((v_rec->>'avg_hrv')::double precision, 0),
            coalesce((v_rec->>'avg_spo2')::double precision, 0),
            coalesce((v_rec->>'avg_temp')::double precision, 0),
            coalesce((v_rec->>'sleep_score')::integer, 0),
            coalesce((v_rec->>'readiness_score')::integer, 0),
            coalesce((v_rec->>'activity_score')::integer, 0)
          )
          on conflict (user_id, date) do update set
            total_steps = excluded.total_steps,
            avg_hr = excluded.avg_hr,
            min_hr = excluded.min_hr,
            avg_hrv = excluded.avg_hrv,
            avg_spo2 = excluded.avg_spo2,
            avg_temp = excluded.avg_temp,
            sleep_score = excluded.sleep_score,
            readiness_score = excluded.readiness_score,
            activity_score = excluded.activity_score;
          v_inserted := v_inserted + 1;
        exception when others then v_skipped := v_skipped + 1;
        end;
      end loop;

    elsif v_table = 'baselines' then
      for v_rec in select * from jsonb_array_elements(v_records)
      loop
        begin
          insert into public.baselines (
            user_id, metric, mean, deviation, sample_count, last_updated
          )
          values (
            v_user,
            v_rec->>'metric',
            (v_rec->>'mean')::double precision,
            (v_rec->>'deviation')::double precision,
            (v_rec->>'sample_count')::integer,
            (v_rec->>'last_updated')::double precision
          )
          on conflict (user_id, metric) do update set
            mean = excluded.mean,
            deviation = excluded.deviation,
            sample_count = excluded.sample_count,
            last_updated = excluded.last_updated;
          v_inserted := v_inserted + 1;
        exception when others then v_skipped := v_skipped + 1;
        end;
      end loop;
    end if;
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

-- Pull delta since cursor (ISO timestamp stored in sync_cursors.cursor)
create or replace function public.pull_sync_delta(
  p_device_id uuid,
  p_since_cursor text,
  p_tables text[] default array[
    'heart_rate', 'spo2', 'temperature', 'sleep_phase', 'steps',
    'daily_summary', 'baselines'
  ]
)
returns jsonb
language plpgsql
security invoker
as $$
declare
  v_user uuid := auth.uid();
  v_since timestamptz;
  v_batches jsonb := '[]'::jsonb;
  v_tbl text;
  v_rows jsonb;
  v_new_cursor text;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  v_since := coalesce(nullif(p_since_cursor, '0')::timestamptz, '1970-01-01'::timestamptz);

  foreach v_tbl in array p_tables
  loop
    if v_tbl = 'daily_summary' then
      select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
      into v_rows
      from (
        select date, total_steps, avg_hr, min_hr, avg_hrv, avg_spo2, avg_temp,
               sleep_score, readiness_score, activity_score
        from public.daily_summary
        where user_id = v_user
        limit 500
      ) t;
    elsif v_tbl = 'baselines' then
      select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
      into v_rows
      from (
        select metric, mean, deviation, sample_count, last_updated
        from public.baselines
        where user_id = v_user
      ) t;
    else
      execute format(
        'select coalesce(jsonb_agg(row_to_json(t)), ''[]''::jsonb)
         from (select * from public.%I where user_id = $1 limit 500) t',
        v_tbl
      ) into v_rows using v_user;
    end if;

    if v_rows is not null and v_rows != '[]'::jsonb then
      v_batches := v_batches || jsonb_build_object('table', v_tbl, 'records', v_rows);
    end if;
  end loop;

  v_new_cursor := now()::text;

  return jsonb_build_object('cursor', v_new_cursor, 'batches', v_batches);
end;
$$;

grant execute on function public.pull_sync_delta(uuid, text, text[]) to authenticated;
