-- ============================================================
-- FINANCE HUB — VERSION 1
-- Supabase schema (PostgreSQL + Row Level Security)
-- Run this once in the Supabase SQL editor on a fresh project.
-- ============================================================

-- ------------------------------------------------------------
-- 0. EXTENSIONS
-- ------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- 1. ROLES (Version 1: keep it simple, expand later)
-- ------------------------------------------------------------
-- super_admin  -> full access, all sites, user management
-- accountant   -> transaction entry + reports, assigned sites only
-- site_manager -> transaction entry, assigned sites only, no user mgmt
-- viewer       -> read-only, assigned sites only

-- ------------------------------------------------------------
-- 2. PROFILES  (extends auth.users, 1 row per Finance Hub user)
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  name          text not null,
  mobile        text unique,
  email         text unique,
  role          text not null default 'viewer'
                  check (role in ('super_admin','accountant','site_manager','viewer')),
  status        text not null default 'active'
                  check (status in ('active','inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Which sites a user can see. Empty for super_admin = all sites (checked in app logic).
-- NOTE: the FK to sites is added later (section 12), after the sites table exists.
create table if not exists public.user_site_access (
  user_id  uuid not null references public.profiles(id) on delete cascade,
  site_id  uuid not null,
  primary key (user_id, site_id)
);

-- ------------------------------------------------------------
-- 3. SITES
-- ------------------------------------------------------------
create table if not exists public.sites (
  id          uuid primary key default gen_random_uuid(),
  site_name   text not null unique,
  status      text not null default 'active' check (status in ('active','inactive')),
  created_at  timestamptz not null default now()
);

insert into public.sites (site_name) values
  ('Zinnia'),
  ('Whispering Grooves'),
  ('Genial')
on conflict (site_name) do nothing;

-- ------------------------------------------------------------
-- 4. PARTIES  (suppliers / contractors / labour / clients / other)
-- ------------------------------------------------------------
create table if not exists public.parties (
  id           uuid primary key default gen_random_uuid(),
  party_name   text not null,
  party_type   text not null check (party_type in ('Supplier','Contractor','Labour','Client','Other')),
  mobile       text,
  email        text,
  gstin        text,
  address      text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (party_name, party_type)
);

-- ------------------------------------------------------------
-- 5. EXPENSE TRANSACTIONS  (Supplier Expenses + Self Expenses)
-- ------------------------------------------------------------
create table if not exists public.expense_transactions (
  id                  uuid primary key default gen_random_uuid(),
  site_id             uuid not null references public.sites(id),
  transaction_date    date not null,
  description         text,
  challan_no          text,
  party_id            uuid references public.parties(id),
  party_name_snapshot text,
  material_name       text,
  expense_head        text,
  expense_type        text,               -- from "Type" column (Genial sheet)
  amount              numeric(14,2) not null check (amount > 0),
  bill_amount         numeric(14,2), -- total billed amount if different from amount paid (e.g. partial payment)
  payment_status      text,
  paid_by             text,
  payment_mode        text check (payment_mode in ('Cash','Online')),
  remark              text,
  source_sheet        text,               -- excel traceability
  source_row          int,
  source_type         text default 'manual' check (source_type in ('manual','import')),
  status              text not null default 'active' check (status in ('active','archived')),
  created_by          uuid references public.profiles(id),
  created_at          timestamptz not null default now(),
  updated_by          uuid references public.profiles(id),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_expense_date  on public.expense_transactions (transaction_date);
create index if not exists idx_expense_site  on public.expense_transactions (site_id);
create index if not exists idx_expense_party on public.expense_transactions (party_id);
create index if not exists idx_expense_mode  on public.expense_transactions (payment_mode);

-- Duplicate-protection helper (Part 3 §8): sheet + row + site + date + amount.
-- (Party name is intentionally NOT part of this key — see import.html for why.)
create unique index if not exists uq_expense_import_dedupe
  on public.expense_transactions (source_sheet, source_row, site_id, transaction_date, amount)
  where source_type = 'import';

-- ------------------------------------------------------------
-- 6. CLIENT PAYMENTS
-- ------------------------------------------------------------
create table if not exists public.client_payments (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid references public.parties(id),
  client_name     text not null,
  site_id         uuid not null references public.sites(id),
  payment_date    date not null,
  amount          numeric(14,2) not null check (amount > 0),
  payment_mode    text not null check (payment_mode in ('Cash','Online')),
  gst_applicable  boolean not null default false,
  gst_amount      numeric(14,2) default 0,
  utr_number      text,
  remarks         text,
  status          text not null default 'active' check (status in ('active','archived')),
  created_by      uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_by      uuid references public.profiles(id),
  updated_at      timestamptz not null default now()
);

create index if not exists idx_client_pay_date   on public.client_payments (payment_date);
create index if not exists idx_client_pay_site   on public.client_payments (site_id);
create index if not exists idx_client_pay_client on public.client_payments (client_id);

-- ------------------------------------------------------------
-- 7. CONTRACTOR PAYMENTS
-- ------------------------------------------------------------
create table if not exists public.contractor_payments (
  id             uuid primary key default gen_random_uuid(),
  contractor_id  uuid references public.parties(id),
  contractor_name_snapshot text,
  site_id        uuid not null references public.sites(id),
  payment_date   date not null,
  amount         numeric(14,2) not null check (amount > 0),
  bill_amount    numeric(14,2), -- total billed amount if different from amount paid
  payment_mode   text not null check (payment_mode in ('Cash','Online')),
  payment_status text,
  remarks        text,
  status         text not null default 'active' check (status in ('active','archived')),
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles(id),
  updated_at     timestamptz not null default now()
);

create index if not exists idx_contractor_date on public.contractor_payments (payment_date);
create index if not exists idx_contractor_site on public.contractor_payments (site_id);

-- ------------------------------------------------------------
-- 8. LABOUR PAYMENTS
-- ------------------------------------------------------------
create table if not exists public.labour_payments (
  id            uuid primary key default gen_random_uuid(),
  labour_id     uuid references public.parties(id),
  labour_name_snapshot text,
  site_id       uuid not null references public.sites(id),
  payment_date  date not null,
  amount        numeric(14,2) not null check (amount > 0),
  payment_mode  text not null check (payment_mode in ('Cash','Online')),
  payment_status text,
  remarks       text,
  status        text not null default 'active' check (status in ('active','archived')),
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles(id),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_labour_date on public.labour_payments (payment_date);
create index if not exists idx_labour_site on public.labour_payments (site_id);

-- ------------------------------------------------------------
-- 9. ATTACHMENTS  (metadata; files live in Supabase Storage bucket 'attachments')
-- ------------------------------------------------------------
create table if not exists public.attachments (
  id                uuid primary key default gen_random_uuid(),
  transaction_table text not null check (transaction_table in
                       ('client_payments','expense_transactions','contractor_payments','labour_payments')),
  transaction_id    uuid not null,
  file_path         text not null,     -- storage object path
  file_name         text not null,
  file_type         text,
  uploaded_by       uuid references public.profiles(id),
  created_at        timestamptz not null default now()
);

create index if not exists idx_attach_txn on public.attachments (transaction_table, transaction_id);

-- ------------------------------------------------------------
-- 10. AUDIT LOG
-- ------------------------------------------------------------
create table if not exists public.audit_log (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references public.profiles(id),
  action            text not null,        -- e.g. 'create','update','archive','restore','login'
  transaction_table text,
  record_id         uuid,
  details           jsonb,
  created_at        timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 11. IMPORT LOG  (one row per Excel import run, for the import summary screen)
-- ------------------------------------------------------------
create table if not exists public.import_runs (
  id                 uuid primary key default gen_random_uuid(),
  file_name          text,
  imported_by        uuid references public.profiles(id),
  rows_processed     int default 0,
  rows_imported      int default 0,
  rows_duplicate     int default 0,
  rows_invalid       int default 0,
  total_amount       numeric(14,2) default 0,
  summary            jsonb,
  created_at         timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 12. user_site_access FK now that sites exists (fix ordering)
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'user_site_access_site_id_fkey'
  ) then
    alter table public.user_site_access
      add constraint user_site_access_site_id_fkey
      foreign key (site_id) references public.sites(id) on delete cascade;
  end if;
exception when others then null;
end $$;

-- ------------------------------------------------------------
-- 13. HELPER: is current user super_admin / has site access
-- ------------------------------------------------------------
create or replace function public.is_super_admin()
returns boolean language sql stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin' and status = 'active'
  );
$$;

create or replace function public.has_site_access(p_site_id uuid)
returns boolean language sql stable as $$
  select public.is_super_admin()
    or exists (
      select 1 from public.user_site_access usa
      join public.profiles p on p.id = usa.user_id
      where usa.user_id = auth.uid() and usa.site_id = p_site_id and p.status = 'active'
    );
$$;

-- ------------------------------------------------------------
-- 14. ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.profiles              enable row level security;
alter table public.user_site_access      enable row level security;
alter table public.sites                 enable row level security;
alter table public.parties               enable row level security;
alter table public.expense_transactions  enable row level security;
alter table public.client_payments       enable row level security;
alter table public.contractor_payments   enable row level security;
alter table public.labour_payments       enable row level security;
alter table public.attachments           enable row level security;
alter table public.audit_log             enable row level security;
alter table public.import_runs           enable row level security;

-- profiles: users can see their own row; super_admin sees all
create policy profiles_self_or_admin on public.profiles
  for select using (id = auth.uid() or public.is_super_admin());
create policy profiles_admin_write on public.profiles
  for all using (public.is_super_admin()) with check (public.is_super_admin());

-- sites: any active authenticated user can read; only super_admin writes
create policy sites_read on public.sites for select using (auth.role() = 'authenticated');
create policy sites_admin_write on public.sites
  for all using (public.is_super_admin()) with check (public.is_super_admin());

-- parties: readable by anyone authenticated (needed for searchable dropdowns), write by active users
create policy parties_read on public.parties for select using (auth.role() = 'authenticated');
create policy parties_write on public.parties for insert with check (auth.role() = 'authenticated');
create policy parties_update on public.parties for update using (auth.role() = 'authenticated');

-- transaction tables: site-scoped access
create policy expense_site_scoped on public.expense_transactions
  for all using (public.has_site_access(site_id)) with check (public.has_site_access(site_id));

create policy client_pay_site_scoped on public.client_payments
  for all using (public.has_site_access(site_id)) with check (public.has_site_access(site_id));

create policy contractor_site_scoped on public.contractor_payments
  for all using (public.has_site_access(site_id)) with check (public.has_site_access(site_id));

create policy labour_site_scoped on public.labour_payments
  for all using (public.has_site_access(site_id)) with check (public.has_site_access(site_id));

-- attachments: readable/writable by authenticated users (fine-grained control handled via signed URLs)
create policy attachments_rw on public.attachments
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- audit log: insert by anyone authenticated, read by super_admin only
create policy audit_insert on public.audit_log for insert with check (auth.role() = 'authenticated');
create policy audit_read on public.audit_log for select using (public.is_super_admin());

-- import runs: super_admin + accountant
create policy import_runs_rw on public.import_runs
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ------------------------------------------------------------
-- 15. STORAGE BUCKET for attachments (create via dashboard or here)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

create policy "attachments bucket read" on storage.objects
  for select using (bucket_id = 'attachments' and auth.role() = 'authenticated');
create policy "attachments bucket write" on storage.objects
  for insert with check (bucket_id = 'attachments' and auth.role() = 'authenticated');

-- ------------------------------------------------------------
-- 16. AGGREGATE FUNCTIONS (dashboard/site totals)
-- ------------------------------------------------------------
-- IMPORTANT: PostgREST (Supabase's REST layer) caps any plain SELECT at 1000 rows
-- by default. Once a table holds more than ~1000 active rows, summing on the
-- client by fetching all rows silently undercounts. These functions do the sum
-- in the database instead, so totals are always correct regardless of row count.
-- They run as SECURITY INVOKER (the default), so each caller's RLS site-scoping
-- still applies automatically.

create or replace function public.dashboard_summary(p_site_id uuid default null)
returns table (
  client_total numeric, client_cash numeric, client_online numeric, gst_total numeric,
  expense_total numeric, expense_cash numeric, expense_online numeric,
  contractor_total numeric, contractor_cash numeric, contractor_online numeric,
  labour_total numeric, labour_cash numeric, labour_online numeric
)
language sql stable as $$
  select
    coalesce((select sum(amount) from client_payments where status='active' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from client_payments where status='active' and payment_mode='Cash' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from client_payments where status='active' and payment_mode='Online' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(gst_amount) from client_payments where status='active' and gst_applicable=true and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and payment_mode='Cash' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and payment_mode='Online' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from contractor_payments where status='active' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from contractor_payments where status='active' and payment_mode='Cash' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from contractor_payments where status='active' and payment_mode='Online' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from labour_payments where status='active' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from labour_payments where status='active' and payment_mode='Cash' and (p_site_id is null or site_id=p_site_id)),0),
    coalesce((select sum(amount) from labour_payments where status='active' and payment_mode='Online' and (p_site_id is null or site_id=p_site_id)),0);
$$;

create or replace function public.site_summary()
returns table (site_id uuid, site_name text, total_receipts numeric, total_expenses numeric)
language sql stable as $$
  select s.id, s.site_name,
    coalesce((select sum(amount) from client_payments where status='active' and site_id=s.id),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and site_id=s.id),0)
  from public.sites s where s.status='active' order by s.site_name;
$$;

-- Full site-wise matrix (all 4 ledgers + cash/online + GST) for the Reports → Site Summary view.
create or replace function public.site_summary_full()
returns table (
  site_id uuid, site_name text,
  client_total numeric, client_cash numeric, client_online numeric, gst_total numeric,
  expense_total numeric, expense_cash numeric, expense_online numeric,
  contractor_total numeric, contractor_cash numeric, contractor_online numeric,
  labour_total numeric, labour_cash numeric, labour_online numeric
)
language sql stable as $$
  select s.id, s.site_name,
    coalesce((select sum(amount) from client_payments where status='active' and site_id=s.id),0),
    coalesce((select sum(amount) from client_payments where status='active' and payment_mode='Cash' and site_id=s.id),0),
    coalesce((select sum(amount) from client_payments where status='active' and payment_mode='Online' and site_id=s.id),0),
    coalesce((select sum(gst_amount) from client_payments where status='active' and gst_applicable=true and site_id=s.id),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and site_id=s.id),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and payment_mode='Cash' and site_id=s.id),0),
    coalesce((select sum(amount) from expense_transactions where status='active' and payment_mode='Online' and site_id=s.id),0),
    coalesce((select sum(amount) from contractor_payments where status='active' and site_id=s.id),0),
    coalesce((select sum(amount) from contractor_payments where status='active' and payment_mode='Cash' and site_id=s.id),0),
    coalesce((select sum(amount) from contractor_payments where status='active' and payment_mode='Online' and site_id=s.id),0),
    coalesce((select sum(amount) from labour_payments where status='active' and site_id=s.id),0),
    coalesce((select sum(amount) from labour_payments where status='active' and payment_mode='Cash' and site_id=s.id),0),
    coalesce((select sum(amount) from labour_payments where status='active' and payment_mode='Online' and site_id=s.id),0)
  from public.sites s where s.status='active' order by s.site_name;
$$;

-- ============================================================
-- END OF SCHEMA
-- After running this:
-- 1. Create your first super_admin: sign up a user via Supabase Auth,
--    then run:
--    insert into public.profiles (id, name, email, role, status)
--    values ('<auth-user-uuid>', 'Your Name', 'you@example.com', 'super_admin', 'active');
-- 2. Grant that user access to all 3 sites in user_site_access (optional —
--    super_admin already bypasses site checks via is_super_admin()).
-- ============================================================
