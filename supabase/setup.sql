-- Lead Tracker: database setup (used from step 2, when accounts and automatic intake are switched on).
-- Runs in the same Supabase project as the Invoice App, so one login works for both.
-- Paste into Supabase → SQL Editor → New query, then press Run. Safe to re-run.

create table if not exists public.lead_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
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
  bad_reason text,                                   -- set when the lead is marked bad
  credit_status text check (credit_status in ('none','requested','credited','denied')),
  vendor_lead_id text,                               -- the vendor's own ID, to stop duplicates on intake
  created_at timestamptz not null default now()
);
create unique index if not exists leads_vendor_unique on public.leads (user_id, source_id, vendor_lead_id) where vendor_lead_id is not null;
create index if not exists leads_user_created on public.leads (user_id, created_at desc);

create table if not exists public.lead_attempts (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  how text not null check (how in ('call','text','email','visit')),
  result text not null check (result in ('noanswer','voicemail','sent','spoke')),
  note text,
  at timestamptz not null default now()
);

-- Row Level Security: each signed-in customer can only see and change their own rows.
do $$
declare t text;
begin
  foreach t in array array['lead_sources','leads','lead_attempts'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "Own rows" on public.%I', t);
    execute format('create policy "Own rows" on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
  end loop;
end $$;
