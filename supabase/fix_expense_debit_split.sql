-- ============================================================
-- FIX: separate 'Expenses' (total bill) from 'Debit' (actual paid)
-- amount = actual paid (Debit-priority); bill_amount = total billed (Expenses-priority)
-- Only rows whose figures actually change are included below.
-- ============================================================

alter table public.expense_transactions add column if not exists bill_amount numeric(14,2);
alter table public.contractor_payments add column if not exists bill_amount numeric(14,2);

-- default: for every row not explicitly listed below, bill_amount = amount (no change)
update public.expense_transactions set bill_amount = amount where bill_amount is null;
update public.contractor_payments set bill_amount = amount where bill_amount is null;

-- corrections for rows where Expenses and Debit genuinely differed
with corrections(source_sheet, source_row, site_name, correct_amount, correct_bill) as (
  values
  ('Expense Zinnia', 198, 'Zinnia', 50000, 87350),
  ('Expense Zinnia', 264, 'Zinnia', 20000, 41500),
  ('Expense Zinnia', 351, 'Zinnia', 15000, 34342),
  ('Expense Zinnia', 361, 'Zinnia', 34030, 14688),
  ('Expense Zinnia', 392, 'Zinnia', 37600, 79600),
  ('Expense Zinnia', 415, 'Zinnia', 42000, 100800),
  ('Expense Zinnia', 442, 'Zinnia', 169200, 68400),
  ('Expense Zinnia', 477, 'Zinnia', 32500, 30500),
  ('Expense Zinnia', 489, 'Zinnia', 100000, 109800),
  ('Expense Zinnia', 503, 'Zinnia', 400000, 30600),
  ('Expense Zinnia', 552, 'Zinnia', 100000, 788800),
  ('Expense Zinnia', 558, 'Zinnia', 50000, 106200),
  ('Expense Zinnia', 574, 'Zinnia', 100000, 323620),
  ('Expense Zinnia', 603, 'Zinnia', 200000, 229710),
  ('Expense Zinnia', 618, 'Zinnia', 200000, 305660),
  ('Expense Zinnia', 619, 'Zinnia', 22750, 102600),
  ('Expense Zinnia', 635, 'Zinnia', 50000, 102600),
  ('Expense Zinnia', 663, 'Zinnia', 100000, 47560),
  ('Expense Zinnia', 664, 'Zinnia', 250000, 1519000),
  ('Expense Zinnia', 677, 'Zinnia', 150000, 314360),
  ('Expense Zinnia', 708, 'Zinnia', 100000, 146740),
  ('Expense Zinnia', 728, 'Zinnia', 94000, 94400),
  ('Expense Zinnia', 752, 'Zinnia', 100000, 334080),
  ('Expense Zinnia', 791, 'Zinnia', 100000, 102600),
  ('Expense Zinnia', 805, 'Zinnia', 147000, 147500),
  ('Expense Zinnia', 811, 'Zinnia', 300000, 8850),
  ('Expense Zinnia', 826, 'Zinnia', 100000, 265060),
  ('Expense Zinnia', 879, 'Zinnia', 200000, 232000),
  ('Expense Whispering grooves', 185, 'Whispering Grooves', 50000, 1025000),
  ('Expense Whispering grooves', 189, 'Whispering Grooves', 100000, 227980),
  ('Expense Whispering grooves', 223, 'Whispering Grooves', 100000, 348500),
  ('Expense Whispering grooves', 242, 'Whispering Grooves', 100000, 308400),
  ('Expense Whispering grooves', 285, 'Whispering Grooves', 50000, 190000),
  ('Expense Whispering grooves', 296, 'Whispering Grooves', 150000, 59455),
  ('Expense Genial', 286, 'Genial', 45000, 2170000),
  ('Expense Genial', 867, 'Genial', 4300, 4390),
  ('Expense Genial', 883, 'Genial', 41700, 41761),
  ('Expense Genial', 891, 'Genial', 80000, 40000),
  ('Expense Genial', 920, 'Genial', 50000, 6750000),
  ('Expense Genial', 1128, 'Genial', 53492, 113492),
  ('Expense Genial', 1130, 'Genial', 20000, 11000),
  ('Expense Genial', 1160, 'Genial', 100000, 20000),
  ('Expense Genial', 1179, 'Genial', 100000, 2160000),
  ('Expense Genial', 1316, 'Genial', 67500, 76250),
  ('Expense Genial', 1322, 'Genial', 50000, 184800),
  ('Expense Genial', 1398, 'Genial', 100000, 248900),
  ('Expense Genial', 1512, 'Genial', 100000, 193120)
)
update public.expense_transactions et
set amount = c.correct_amount, bill_amount = c.correct_bill
from corrections c join public.sites s on s.site_name = c.site_name
where et.source_sheet = c.source_sheet and et.source_row = c.source_row and et.site_id = s.id and et.source_type = 'import';

with corrections(source_sheet, source_row, site_name, correct_amount, correct_bill) as (
  values
  ('Expense Zinnia', 198, 'Zinnia', 50000, 87350),
  ('Expense Zinnia', 264, 'Zinnia', 20000, 41500),
  ('Expense Zinnia', 351, 'Zinnia', 15000, 34342),
  ('Expense Zinnia', 361, 'Zinnia', 34030, 14688),
  ('Expense Zinnia', 392, 'Zinnia', 37600, 79600),
  ('Expense Zinnia', 415, 'Zinnia', 42000, 100800),
  ('Expense Zinnia', 442, 'Zinnia', 169200, 68400),
  ('Expense Zinnia', 477, 'Zinnia', 32500, 30500),
  ('Expense Zinnia', 489, 'Zinnia', 100000, 109800),
  ('Expense Zinnia', 503, 'Zinnia', 400000, 30600),
  ('Expense Zinnia', 552, 'Zinnia', 100000, 788800),
  ('Expense Zinnia', 558, 'Zinnia', 50000, 106200),
  ('Expense Zinnia', 574, 'Zinnia', 100000, 323620),
  ('Expense Zinnia', 603, 'Zinnia', 200000, 229710),
  ('Expense Zinnia', 618, 'Zinnia', 200000, 305660),
  ('Expense Zinnia', 619, 'Zinnia', 22750, 102600),
  ('Expense Zinnia', 635, 'Zinnia', 50000, 102600),
  ('Expense Zinnia', 663, 'Zinnia', 100000, 47560),
  ('Expense Zinnia', 664, 'Zinnia', 250000, 1519000),
  ('Expense Zinnia', 677, 'Zinnia', 150000, 314360),
  ('Expense Zinnia', 708, 'Zinnia', 100000, 146740),
  ('Expense Zinnia', 728, 'Zinnia', 94000, 94400),
  ('Expense Zinnia', 752, 'Zinnia', 100000, 334080),
  ('Expense Zinnia', 791, 'Zinnia', 100000, 102600),
  ('Expense Zinnia', 805, 'Zinnia', 147000, 147500),
  ('Expense Zinnia', 811, 'Zinnia', 300000, 8850),
  ('Expense Zinnia', 826, 'Zinnia', 100000, 265060),
  ('Expense Zinnia', 879, 'Zinnia', 200000, 232000),
  ('Expense Whispering grooves', 185, 'Whispering Grooves', 50000, 1025000),
  ('Expense Whispering grooves', 189, 'Whispering Grooves', 100000, 227980),
  ('Expense Whispering grooves', 223, 'Whispering Grooves', 100000, 348500),
  ('Expense Whispering grooves', 242, 'Whispering Grooves', 100000, 308400),
  ('Expense Whispering grooves', 285, 'Whispering Grooves', 50000, 190000),
  ('Expense Whispering grooves', 296, 'Whispering Grooves', 150000, 59455),
  ('Expense Genial', 286, 'Genial', 45000, 2170000),
  ('Expense Genial', 867, 'Genial', 4300, 4390),
  ('Expense Genial', 883, 'Genial', 41700, 41761),
  ('Expense Genial', 891, 'Genial', 80000, 40000),
  ('Expense Genial', 920, 'Genial', 50000, 6750000),
  ('Expense Genial', 1128, 'Genial', 53492, 113492),
  ('Expense Genial', 1130, 'Genial', 20000, 11000),
  ('Expense Genial', 1160, 'Genial', 100000, 20000),
  ('Expense Genial', 1179, 'Genial', 100000, 2160000),
  ('Expense Genial', 1316, 'Genial', 67500, 76250),
  ('Expense Genial', 1322, 'Genial', 50000, 184800),
  ('Expense Genial', 1398, 'Genial', 100000, 248900),
  ('Expense Genial', 1512, 'Genial', 100000, 193120)
)
update public.contractor_payments cp
set amount = c.correct_amount, bill_amount = c.correct_bill
from corrections c join public.sites s on s.site_name = c.site_name
where cp.source_sheet = c.source_sheet and cp.source_row = c.source_row and cp.site_id = s.id and cp.source_type = 'import';

-- verify: should show the corrected rows now differing from bill_amount
select source_sheet, source_row, amount, bill_amount from public.expense_transactions
where amount <> bill_amount order by source_sheet, source_row;