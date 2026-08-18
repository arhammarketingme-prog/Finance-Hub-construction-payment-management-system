-- ============================================================
-- FINANCE HUB — CLEANUP: duplicate-import rows
-- Run this if the diagnostic query showed duplicate (source_sheet, source_row, site_id)
-- groups. Safe to run even if there are zero duplicates — it simply does nothing then.
-- Nothing is permanently deleted; extra copies are archived (soft delete).
-- ============================================================

-- 1) Archive duplicate expense_transactions rows, keeping the earliest-created copy
--    per (source_sheet, source_row, site_id). The earliest copy is kept because it's
--    the one that went through the ledger reclassification migration correctly.
with ranked as (
  select id, row_number() over (
    partition by source_sheet, source_row, site_id
    order by created_at asc
  ) as rn
  from public.expense_transactions
  where status = 'active' and source_type = 'import'
)
update public.expense_transactions
set status = 'archived'
where id in (select id from ranked where rn > 1);

-- 2) Same cleanup for contractor_payments (in case a duplicate "work" row was also
--    moved there during a repeat import).
with ranked as (
  select id, row_number() over (
    partition by source_sheet, source_row, site_id
    order by created_at asc
  ) as rn
  from public.contractor_payments
  where status = 'active' and source_type = 'import' and source_sheet is not null
)
update public.contractor_payments
set status = 'archived'
where id in (select id from ranked where rn > 1);

-- 3) Harden the DB-level duplicate guard so this can't happen again, even if the
--    app-side check is ever bypassed. Party name is dropped from the key (a name can
--    be auto-corrected later, which must not make an already-imported row look "new").
drop index if exists public.uq_expense_import_dedupe;
create unique index uq_expense_import_dedupe
  on public.expense_transactions (source_sheet, source_row, site_id, transaction_date, amount)
  where source_type = 'import';

-- 4) Verify: this should now return zero rows.
select source_sheet, source_row, site_id, count(*) as cnt
from public.expense_transactions
where status = 'active' and source_type = 'import'
group by source_sheet, source_row, site_id
having count(*) > 1;

-- ============================================================
-- END OF CLEANUP
-- ============================================================
