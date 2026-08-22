-- Adds Budget vs Actual tracking. Safe to run even if already applied.
alter table public.sites add column if not exists budget numeric(14,2);
