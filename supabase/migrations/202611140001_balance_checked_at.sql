-- Store the balance check as a moment in time, not just a day, so entries
-- added later on the same day as the check count against "Balance now".
--
-- Existing checks only have a date. Each becomes the last second of that day
-- in India time, so entries already made that day are not subtracted from
-- the checked balance a second time. That gives the same "Balance now" the
-- app showed before this change.
alter table public.financial_profiles
  alter column balance_as_of drop default,
  alter column balance_as_of type timestamptz
    using ((balance_as_of + 1)::timestamp - interval '1 second')
      at time zone 'Asia/Kolkata',
  alter column balance_as_of set default now();
