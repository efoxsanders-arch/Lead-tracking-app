-- Lead Tracker: database setup for accounts and automatic lead intake.
-- Runs in the same Supabase project as the Invoice App, so one login works for both.
-- Paste this whole file into Supabase → SQL Editor → New query, then press Run. Safe to re-run.

-- ---------- Tables ----------
create table if not exists public.lead_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  kind text not null default 'other',              -- google_ads, google_lsa, angi, thumbtack or other
  cost_per_lead numeric(10,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source_id uuid references public.lead_sources (id) on delete set null,
  name text, phone text, email text, service text, notes text,
  cost numeric(10,2) not null default 0,
  status text not null default 'new' check (status in ('new','contacted','quoted','won','lost')),
  follow_up date,
  quote_amount numeric(12,2), won_amount numeric(12,2), lost_reason text,
  bad_reason text,                                 -- set when the lead is marked bad
  credit_status text check (credit_status in ('none','requested','credited','denied')),
  attempts jsonb not null default '[]'::jsonb,     -- every call, text, email or visit
  vendor_lead_id text,                             -- the vendor's own ID, to stop duplicates
  raw jsonb,                                       -- what the vendor sent, kept for troubleshooting
  created_at timestamptz not null default now()
);
create unique index if not exists leads_vendor_unique on public.leads (user_id, source_id, vendor_lead_id) where vendor_lead_id is not null;
create index if not exists leads_user_created on public.leads (user_id, created_at desc);

create table if not exists public.lead_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  untouched_min integer not null default 15,
  stale_days integer not null default 3
);

-- One private key per account. It goes in the web address each lead vendor sends leads to.
create table if not exists public.lead_intake_keys (
  user_id uuid primary key references auth.users (id) on delete cascade,
  key text not null unique check (length(key) >= 24),
  created_at timestamptz not null default now()
);

-- ---------- Row Level Security: each customer can only see and change their own rows ----------
do $$
declare t text;
begin
  foreach t in array array['lead_sources','leads','lead_settings','lead_intake_keys'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "Own rows" on public.%I', t);
    execute format('create policy "Own rows" on public.%I for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
  end loop;
end $$;

-- ---------- Intake: called only by the lead-intake function, never by the app ----------
-- Finds the account that owns the key, files the lead under the right source,
-- and returns the lead's ID. Sending the same vendor lead twice returns the first one.
create or replace function public.lead_intake(p_key text, p_kind text, p_lead jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_kind text := case when p_kind in ('google_ads','google_lsa','angi','thumbtack') then p_kind else 'other' end;
  v_source_id uuid;
  v_default_cost numeric;
  v_vendor_id text := nullif(p_lead->>'vendor_lead_id', '');
  v_id uuid;
begin
  select user_id into v_user from public.lead_intake_keys where key = p_key;
  if v_user is null or p_key is null then
    raise exception 'invalid_key';
  end if;

  select id, cost_per_lead into v_source_id, v_default_cost
    from public.lead_sources where user_id = v_user and kind = v_kind order by created_at, id limit 1;
  if v_source_id is null then
    insert into public.lead_sources (user_id, name, kind)
    values (v_user, case v_kind when 'google_ads' then 'Google Ads' when 'google_lsa' then 'Google Local Services'
                                when 'angi' then 'Angi / HomeAdvisor' when 'thumbtack' then 'Thumbtack' else 'Other' end, v_kind)
    returning id, cost_per_lead into v_source_id, v_default_cost;
  end if;

  if v_vendor_id is not null then
    select id into v_id from public.leads where user_id = v_user and source_id = v_source_id and vendor_lead_id = v_vendor_id;
    if v_id is not null then return v_id; end if;
  end if;

  begin
    insert into public.leads (user_id, source_id, name, phone, email, service, notes, cost, vendor_lead_id, raw)
    values (v_user, v_source_id,
            left(p_lead->>'name', 200), left(p_lead->>'phone', 60), left(p_lead->>'email', 200),
            left(p_lead->>'service', 300), left(p_lead->>'notes', 4000),
            coalesce(nullif(p_lead->>'cost', '')::numeric, v_default_cost, 0),
            v_vendor_id, p_lead->'raw')
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.leads where user_id = v_user and source_id = v_source_id and vendor_lead_id = v_vendor_id;
  end;
  return v_id;
end;
$$;

revoke execute on function public.lead_intake(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.lead_intake(text, text, jsonb) to service_role;

-- ---------- Live updates: lets the app show a new lead the moment it arrives ----------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'leads') then
    alter publication supabase_realtime add table public.leads;
  end if;
end $$;
