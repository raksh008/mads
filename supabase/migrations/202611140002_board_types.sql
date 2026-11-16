-- Boards are either a Budget (an approximate monthly limit) or a Bill (a
-- fixed amount due on a day of the month). Existing boards become budgets.
alter table public.expense_boards
  add column if not exists board_type text not null default 'budget'
    check (board_type in ('budget', 'bill')),
  add column if not exists due_day smallint
    check (due_day between 1 and 31);
