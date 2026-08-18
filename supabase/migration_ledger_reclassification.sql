-- ============================================================
-- FINANCE HUB — MIGRATION: name normalization + ledger reclassification
-- Run this ONCE, after schema.sql. It permanently changes existing data —
-- read the whole file before running, and run the PREVIEW section first.
-- ============================================================

-- ------------------------------------------------------------
-- PREVIEW (read-only) — run this first to see counts before committing.
-- ------------------------------------------------------------
-- select
--   (select count(*) from expense_transactions where status='active'
--      and (coalesce(party_name_snapshot,'') ~* '\ywork\y' or coalesce(description,'') ~* '\ywork\y')
--      and not (coalesce(party_name_snapshot,'') ~* 'material' or coalesce(description,'') ~* 'material')) as will_move_to_contractor,
--   (select count(*) from expense_transactions where status='active'
--      and (coalesce(party_name_snapshot,'') ~* 'material' or coalesce(description,'') ~* 'material')) as will_tag_material,
--   (select count(*) from expense_transactions where status='active'
--      and (coalesce(party_name_snapshot,'') ~* 'excavation' or coalesce(description,'') ~* 'excavation'
--           or coalesce(party_name_snapshot,'') ~* '\yjcb\y' or coalesce(description,'') ~* '\yjcb\y')
--      and not (coalesce(party_name_snapshot,'') ~* 'material' or coalesce(description,'') ~* 'material')
--      and not (coalesce(party_name_snapshot,'') ~* '\ywork\y' or coalesce(description,'') ~* '\ywork\y')) as will_tag_machinery;

-- ------------------------------------------------------------
-- 1) New columns (safe/additive)
-- ------------------------------------------------------------
alter table public.expense_transactions add column if not exists ledger_category text;
alter table public.contractor_payments add column if not exists source_sheet text;
alter table public.contractor_payments add column if not exists source_row int;
alter table public.contractor_payments add column if not exists source_type text default 'manual';

-- ------------------------------------------------------------
-- 2) Auto-correct spelling/case variants of the same party name
--    (e.g. "Shivaji Pawar" / "shivaji pawar" / "Shivaji pawar" -> one canonical name).
--    Only merges names that are identical once trimmed + lowercased — it will NOT
--    guess-merge genuinely different names or abbreviations.
-- ------------------------------------------------------------
do $$
declare
  rec record;
  canonical_id uuid;
  canonical_name text;
begin
  for rec in
    select lower(trim(party_name)) as name_key, party_type
    from public.parties
    group by lower(trim(party_name)), party_type
    having count(*) > 1
  loop
    select p.id, p.party_name into canonical_id, canonical_name
    from public.parties p
    where lower(trim(p.party_name)) = rec.name_key and p.party_type = rec.party_type
    order by (
      (select count(*) from public.client_payments where client_id = p.id) +
      (select count(*) from public.expense_transactions where party_id = p.id) +
      (select count(*) from public.contractor_payments where contractor_id = p.id) +
      (select count(*) from public.labour_payments where labour_id = p.id)
    ) desc,
    (p.party_name = initcap(p.party_name)) desc,
    p.party_name
    limit 1;

    update public.client_payments set client_id = canonical_id
      where client_id in (select id from public.parties where lower(trim(party_name)) = rec.name_key and party_type = rec.party_type and id <> canonical_id);
    update public.expense_transactions set party_id = canonical_id
      where party_id in (select id from public.parties where lower(trim(party_name)) = rec.name_key and party_type = rec.party_type and id <> canonical_id);
    update public.contractor_payments set contractor_id = canonical_id
      where contractor_id in (select id from public.parties where lower(trim(party_name)) = rec.name_key and party_type = rec.party_type and id <> canonical_id);
    update public.labour_payments set labour_id = canonical_id
      where labour_id in (select id from public.parties where lower(trim(party_name)) = rec.name_key and party_type = rec.party_type and id <> canonical_id);

    update public.client_payments set client_name = canonical_name
      where lower(trim(client_name)) = rec.name_key and client_name <> canonical_name;
    update public.expense_transactions set party_name_snapshot = canonical_name
      where lower(trim(party_name_snapshot)) = rec.name_key and party_name_snapshot <> canonical_name;
    update public.contractor_payments set contractor_name_snapshot = canonical_name
      where lower(trim(contractor_name_snapshot)) = rec.name_key and contractor_name_snapshot <> canonical_name;
    update public.labour_payments set labour_name_snapshot = canonical_name
      where lower(trim(labour_name_snapshot)) = rec.name_key and labour_name_snapshot <> canonical_name;

    delete from public.parties
      where lower(trim(party_name)) = rec.name_key and party_type = rec.party_type and id <> canonical_id;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 3) Reclassify expense_transactions, priority order: Material > Work(Contractor) > Machinery > Misc.
--    "Work" matches are MOVED into contractor_payments; the original row is ARCHIVED
--    (soft delete — kept in the database, excluded from lists/totals), never deleted.
-- ------------------------------------------------------------
insert into public.contractor_payments
  (contractor_id, contractor_name_snapshot, site_id, payment_date, amount, payment_mode, payment_status, remarks, source_sheet, source_row, source_type, created_by)
select
  null, party_name_snapshot, site_id, transaction_date, amount,
  coalesce(payment_mode, 'Cash'), coalesce(payment_status, 'Paid'), description,
  source_sheet, source_row, 'import', created_by
from public.expense_transactions
where status = 'active'
  and (coalesce(party_name_snapshot,'') ~* '\ywork\y' or coalesce(description,'') ~* '\ywork\y')
  and not (coalesce(party_name_snapshot,'') ~* 'material' or coalesce(description,'') ~* 'material');

update public.expense_transactions
set status = 'archived', ledger_category = 'Moved to Contractor'
where status = 'active'
  and (coalesce(party_name_snapshot,'') ~* '\ywork\y' or coalesce(description,'') ~* '\ywork\y')
  and not (coalesce(party_name_snapshot,'') ~* 'material' or coalesce(description,'') ~* 'material');

update public.expense_transactions
set ledger_category = 'Material'
where status = 'active' and ledger_category is null
  and (coalesce(party_name_snapshot,'') ~* 'material' or coalesce(description,'') ~* 'material');

update public.expense_transactions
set ledger_category = 'Machinery Expense'
where status = 'active' and ledger_category is null
  and (coalesce(party_name_snapshot,'') ~* 'excavation' or coalesce(description,'') ~* 'excavation'
       or coalesce(party_name_snapshot,'') ~* '\yjcb\y' or coalesce(description,'') ~* '\yjcb\y');

update public.expense_transactions
set ledger_category = 'Miscellaneous Expenses'
where status = 'active' and ledger_category is null;

-- ------------------------------------------------------------
-- 4) Ledger report RPC — Credit (Client Receipts = Project Cost) vs Debit (by category)
-- ------------------------------------------------------------
create or replace function public.ledger_summary(p_site_id uuid default null)
returns table (
  credit_total numeric, material_total numeric, contractor_total numeric,
  machinery_total numeric, misc_total numeric, labour_total numeric,
  debit_total numeric, balance numeric
)
language sql stable as $$
  with c as (select coalesce(sum(amount),0) v from client_payments where status='active' and (p_site_id is null or site_id=p_site_id)),
       mat as (select coalesce(sum(amount),0) v from expense_transactions where status='active' and ledger_category='Material' and (p_site_id is null or site_id=p_site_id)),
       con as (select coalesce(sum(amount),0) v from contractor_payments where status='active' and (p_site_id is null or site_id=p_site_id)),
       mac as (select coalesce(sum(amount),0) v from expense_transactions where status='active' and ledger_category='Machinery Expense' and (p_site_id is null or site_id=p_site_id)),
       misc as (select coalesce(sum(amount),0) v from expense_transactions where status='active' and ledger_category='Miscellaneous Expenses' and (p_site_id is null or site_id=p_site_id)),
       lab as (select coalesce(sum(amount),0) v from labour_payments where status='active' and (p_site_id is null or site_id=p_site_id))
  select c.v, mat.v, con.v, mac.v, misc.v, lab.v,
         mat.v+con.v+mac.v+misc.v+lab.v,
         c.v - (mat.v+con.v+mac.v+misc.v+lab.v)
  from c, mat, con, mac, misc, lab;
$$;

-- ============================================================
-- END OF MIGRATION
-- ============================================================
