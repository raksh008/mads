-- MADS finance foundation. Apply this migration to the Supabase project before
-- relying on cloud sync. All personal amounts use integer minor units (paise).

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  theme_mode text not null default 'system'
    check (theme_mode in ('system', 'light', 'dark')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.financial_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  monthly_income_minor bigint not null default 0 check (monthly_income_minor >= 0),
  balance_minor bigint not null default 0 check (balance_minor >= 0),
  unpaid_commitments_minor bigint not null default 0 check (unpaid_commitments_minor >= 0),
  planned_savings_minor bigint not null default 0 check (planned_savings_minor >= 0),
  balance_as_of date not null default current_date,
  currency char(3) not null default 'INR',
  updated_at timestamptz not null default now()
);

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  account_type text not null default 'manual'
    check (account_type in ('manual', 'bank', 'cash', 'credit')),
  currency char(3) not null default 'INR',
  provider text,
  external_account_id text,
  created_at timestamptz not null default now(),
  unique (user_id, provider, external_account_id)
);

create table if not exists public.account_balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  balance_minor bigint not null,
  currency char(3) not null default 'INR',
  observed_at timestamptz not null default now(),
  source text not null default 'manual'
);

create table if not exists public.bank_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'revoked', 'error')),
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_aggregator_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.bank_connections(id) on delete cascade,
  provider_consent_id text not null,
  purpose text not null,
  data_types text[] not null default '{}',
  status text not null default 'pending'
    check (status in ('pending', 'active', 'expired', 'revoked', 'rejected')),
  valid_from timestamptz,
  valid_until timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, provider_consent_id)
);

create table if not exists public.connection_sync_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.bank_connections(id) on delete cascade,
  status text not null check (status in ('started', 'succeeded', 'failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  result_count integer not null default 0 check (result_count >= 0),
  provider_error_code text
);

create table if not exists public.expense_boards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 60),
  normalized_name text not null,
  icon_key text not null default 'category',
  merchant_key text,
  logo_url text,
  accent_color text not null default '#147d64',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, normalized_name)
);

create table if not exists public.budget_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  board_id uuid not null references public.expense_boards(id) on delete cascade,
  period_start date not null,
  amount_minor bigint not null default 0 check (amount_minor >= 0),
  currency char(3) not null default 'INR',
  updated_at timestamptz not null default now(),
  unique (board_id, period_start)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  board_id uuid not null references public.expense_boards(id) on delete cascade,
  account_id uuid references public.accounts(id) on delete set null,
  description text not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null default 'INR',
  transaction_kind text not null default 'expense'
    check (transaction_kind in ('expense', 'refund', 'income', 'transfer')),
  status text not null default 'posted'
    check (status in ('pending', 'posted', 'void')),
  merchant_key text,
  icon_key text not null default 'category',
  logo_url text,
  accent_color text not null default '#147d64',
  source text not null default 'manual',
  external_id text,
  transfer_group_id uuid,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, source, external_id)
);

create index if not exists transactions_user_occurred_idx
  on public.transactions (user_id, occurred_at desc);
create index if not exists allocations_user_period_idx
  on public.budget_allocations (user_id, period_start);
create index if not exists boards_user_order_idx
  on public.expense_boards (user_id, sort_order);

create table if not exists public.commitments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  description text not null,
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null default 'INR',
  due_date date,
  status text not null default 'unpaid'
    check (status in ('unpaid', 'paid', 'cancelled')),
  paid_transaction_id uuid references public.transactions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  target_minor bigint not null check (target_minor >= 0),
  currency char(3) not null default 'INR',
  target_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.savings_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid not null references public.savings_goals(id) on delete cascade,
  amount_minor bigint not null check (amount_minor > 0),
  contributed_at timestamptz not null default now(),
  source_transaction_id uuid references public.transactions(id) on delete set null
);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  merchant_key text,
  display_name text not null,
  amount_minor bigint check (amount_minor is null or amount_minor >= 0),
  currency char(3) not null default 'INR',
  cadence text check (cadence in ('weekly', 'monthly', 'quarterly', 'yearly')),
  next_charge_date date,
  status text not null default 'suggested'
    check (status in ('suggested', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now()
);

-- Merchant/category catalogue is backend managed. The Flutter app receives
-- semantic icon keys and permitted logo URLs through resolve_catalog_item().
create table if not exists public.catalog_items (
  item_key text primary key,
  item_type text not null check (item_type in ('category', 'merchant')),
  display_name text not null,
  category_key text,
  icon_key text not null default 'category',
  logo_url text,
  logo_source text,
  license_note text,
  accent_color text not null default '#147d64',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_aliases (
  normalized_alias text primary key,
  item_key text not null references public.catalog_items(item_key) on delete cascade,
  priority integer not null default 0
);

insert into public.catalog_items
  (item_key, item_type, display_name, category_key, icon_key, accent_color)
values
  ('groceries', 'category', 'Groceries', 'groceries', 'groceries', '#3d8d66'),
  ('rent', 'category', 'Rent', 'housing', 'home', '#45628f'),
  ('electricity', 'category', 'Electricity', 'utilities', 'electricity', '#e6a700'),
  ('shopping', 'category', 'Shopping', 'shopping', 'shopping', '#9a65a8'),
  ('beauty', 'category', 'Beauty', 'shopping', 'beauty', '#b55277'),
  ('subscriptions', 'category', 'Subscriptions', 'subscriptions', 'subscriptions', '#147d64'),
  ('travel', 'category', 'Travel', 'travel', 'travel', '#4b68c7'),
  ('health', 'category', 'Health', 'health', 'health', '#d34f64'),
  ('pets', 'category', 'Pets', 'pets', 'pets', '#ad713f'),
  ('dining', 'category', 'Dining out', 'food', 'dining', '#df7547'),
  ('transport', 'category', 'Transport', 'transport', 'transport', '#47719a'),
  ('education', 'category', 'Education', 'education', 'education', '#7562a9'),
  ('internet', 'category', 'Internet and phone', 'utilities', 'internet', '#448a9c'),
  ('entertainment', 'category', 'Entertainment', 'entertainment', 'entertainment', '#9a65a8'),
  ('insurance', 'category', 'Insurance', 'insurance', 'insurance', '#4b7182'),
  ('other', 'category', 'Other', 'other', 'category', '#147d64'),
  ('netflix', 'merchant', 'Netflix', 'subscriptions', 'netflix', '#e50914'),
  ('youtube', 'merchant', 'YouTube', 'subscriptions', 'youtube', '#ff0000'),
  ('chatgpt', 'merchant', 'ChatGPT', 'subscriptions', 'chatgpt', '#10a37f'),
  ('claude', 'merchant', 'Claude', 'subscriptions', 'claude', '#d97757')
on conflict (item_key) do nothing;

insert into public.catalog_aliases (normalized_alias, item_key, priority) values
  ('grocery', 'groceries', 20), ('groceries', 'groceries', 20),
  ('food', 'groceries', 10), ('supermarket', 'groceries', 10),
  ('rent', 'rent', 20), ('home', 'rent', 10), ('housing', 'rent', 10),
  ('electricity', 'electricity', 20), ('electric', 'electricity', 10),
  ('power bill', 'electricity', 10), ('utility', 'electricity', 5),
  ('shopping', 'shopping', 20), ('clothes', 'shopping', 10),
  ('fashion', 'shopping', 10), ('shoes', 'shopping', 5),
  ('beauty', 'beauty', 20), ('makeup', 'beauty', 10), ('salon', 'beauty', 10),
  ('subscriptions', 'subscriptions', 20), ('subscription', 'subscriptions', 20),
  ('netflix', 'netflix', 30), ('netflix com', 'netflix', 30),
  ('youtube', 'youtube', 30), ('youtube premium', 'youtube', 30),
  ('chatgpt', 'chatgpt', 30), ('openai chatgpt', 'chatgpt', 30),
  ('claude', 'claude', 30), ('anthropic claude', 'claude', 30),
  ('travel', 'travel', 20), ('flight', 'travel', 10), ('hotel', 'travel', 10),
  ('health', 'health', 20), ('medical', 'health', 10), ('pharmacy', 'health', 10),
  ('pet', 'pets', 20), ('pets', 'pets', 20), ('vet', 'pets', 10), ('pet care', 'pets', 10),
  ('dining', 'dining', 20), ('restaurant', 'dining', 10), ('cafe', 'dining', 10),
  ('takeaway', 'dining', 10), ('eating out', 'dining', 10),
  ('transport', 'transport', 20), ('fuel', 'transport', 10), ('commute', 'transport', 10),
  ('cab', 'transport', 10), ('uber', 'transport', 10),
  ('education', 'education', 20), ('school', 'education', 10), ('tuition', 'education', 10),
  ('internet', 'internet', 20), ('broadband', 'internet', 10), ('phone bill', 'internet', 10),
  ('entertainment', 'entertainment', 20), ('cinema', 'entertainment', 10),
  ('movies', 'entertainment', 10), ('games', 'entertainment', 10),
  ('insurance', 'insurance', 20), ('premium', 'insurance', 5),
  ('other', 'other', 1)
on conflict (normalized_alias) do nothing;

alter table public.profiles enable row level security;
alter table public.financial_profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.account_balance_snapshots enable row level security;
alter table public.bank_connections enable row level security;
alter table public.account_aggregator_consents enable row level security;
alter table public.connection_sync_events enable row level security;
alter table public.expense_boards enable row level security;
alter table public.budget_allocations enable row level security;
alter table public.transactions enable row level security;
alter table public.commitments enable row level security;
alter table public.savings_goals enable row level security;
alter table public.savings_contributions enable row level security;
alter table public.subscriptions enable row level security;
alter table public.catalog_items enable row level security;
alter table public.catalog_aliases enable row level security;

create policy "Users manage own profile" on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "Users manage own finance profile" on public.financial_profiles
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Users manage own accounts" on public.accounts
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Users manage own balance snapshots" on public.account_balance_snapshots
  for all to authenticated using (user_id = auth.uid()) with check (
    user_id = auth.uid() and exists (
      select 1 from public.accounts a where a.id = account_id and a.user_id = auth.uid()
    )
  );
create policy "Users manage own bank connections" on public.bank_connections
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Users manage own AA consents" on public.account_aggregator_consents
  for all to authenticated using (user_id = auth.uid()) with check (
    user_id = auth.uid() and exists (
      select 1 from public.bank_connections c where c.id = connection_id and c.user_id = auth.uid()
    )
  );
create policy "Users view own connection sync events" on public.connection_sync_events
  for select to authenticated using (user_id = auth.uid());
create policy "Users manage own boards" on public.expense_boards
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Users manage own budgets" on public.budget_allocations
  for all to authenticated using (user_id = auth.uid()) with check (
    user_id = auth.uid() and exists (
      select 1 from public.expense_boards b where b.id = board_id and b.user_id = auth.uid()
    )
  );
create policy "Users manage own transactions" on public.transactions
  for all to authenticated using (user_id = auth.uid()) with check (
    user_id = auth.uid() and exists (
      select 1 from public.expense_boards b where b.id = board_id and b.user_id = auth.uid()
    ) and (
      account_id is null or exists (
        select 1 from public.accounts a where a.id = account_id and a.user_id = auth.uid()
      )
    )
  );
create policy "Users manage own commitments" on public.commitments
  for all to authenticated using (user_id = auth.uid()) with check (
    user_id = auth.uid() and (
      paid_transaction_id is null or exists (
        select 1 from public.transactions t where t.id = paid_transaction_id and t.user_id = auth.uid()
      )
    )
  );
create policy "Users manage own savings goals" on public.savings_goals
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Users manage own savings contributions" on public.savings_contributions
  for all to authenticated using (user_id = auth.uid()) with check (
    user_id = auth.uid() and exists (
      select 1 from public.savings_goals g where g.id = goal_id and g.user_id = auth.uid()
    ) and (
      source_transaction_id is null or exists (
        select 1 from public.transactions t where t.id = source_transaction_id and t.user_id = auth.uid()
      )
    )
  );
create policy "Users manage own subscriptions" on public.subscriptions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Authenticated users read catalogue" on public.catalog_items
  for select to authenticated using (active);
create policy "Authenticated users read aliases" on public.catalog_aliases
  for select to authenticated using (true);

create or replace function public.resolve_catalog_item(p_name text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select trim(regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]+', ' ', 'g')) as value
  ), matched as (
    select i.item_key, i.icon_key, i.logo_url, i.accent_color, i.item_type
    from normalized n
    join public.catalog_aliases a on (
      a.normalized_alias = n.value
      or (' ' || n.value || ' ') like ('% ' || a.normalized_alias || ' %')
    )
    join public.catalog_items i on i.item_key = a.item_key and i.active
    order by (a.normalized_alias = n.value) desc, a.priority desc, length(a.normalized_alias) desc
    limit 1
  )
  select jsonb_build_object(
    'iconKey', coalesce(m.icon_key, 'category'),
    'merchantKey', case when m.item_type = 'merchant' then m.item_key else null end,
    'logoUrl', m.logo_url,
    'accentColor', coalesce(m.accent_color, '#147d64')
  )
  from (select 1) seed
  left join matched m on true;
$$;

revoke all on function public.resolve_catalog_item(text) from public;
grant execute on function public.resolve_catalog_item(text) to authenticated;

-- Household data remains explicitly shared and does not expose private accounts.
create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.household_memberships (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  status text not null default 'active' check (status in ('invited', 'active', 'removed')),
  created_at timestamptz not null default now(),
  unique (household_id, user_id)
);
create table if not exists public.household_shared_expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  description text not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null default 'INR',
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  invite_code text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '7 days',
  consumed_by uuid references auth.users(id) on delete set null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function public.add_household_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.household_memberships (household_id, user_id, role, status)
  values (new.id, new.owner_id, 'owner', 'active')
  on conflict (household_id, user_id) do nothing;
  return new;
end;
$$;
revoke all on function public.add_household_owner_membership() from public;

drop trigger if exists household_owner_membership_after_insert on public.households;
create trigger household_owner_membership_after_insert
  after insert on public.households
  for each row execute function public.add_household_owner_membership();

alter table public.households enable row level security;
alter table public.household_memberships enable row level security;
alter table public.household_shared_expenses enable row level security;
alter table public.household_invites enable row level security;
revoke all on public.household_invites from anon, authenticated;

create or replace function public.is_household_member(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.household_memberships m
    where m.household_id = p_household_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;
revoke all on function public.is_household_member(uuid) from public;
grant execute on function public.is_household_member(uuid) to authenticated;

create or replace function public.create_household_invite(p_household_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := replace(gen_random_uuid()::text, '-', '');
begin
  if auth.uid() is null or not exists (
    select 1 from public.households h
    where h.id = p_household_id and h.owner_id = auth.uid()
  ) then
    raise exception 'Only the household owner can create an invite.';
  end if;
  insert into public.household_invites (household_id, invite_code, created_by)
  values (p_household_id, v_code, auth.uid());
  return v_code;
end;
$$;
revoke all on function public.create_household_invite(uuid) from public;
grant execute on function public.create_household_invite(uuid) to authenticated;

create or replace function public.accept_household_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.household_invites%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in before accepting a household invite.';
  end if;
  select * into v_invite
  from public.household_invites
  where invite_code = lower(trim(p_code))
    and consumed_at is null
    and expires_at > now()
  for update;
  if not found then
    raise exception 'This invite code is invalid, expired, or already used.';
  end if;
  insert into public.household_memberships (household_id, user_id, role, status)
  values (v_invite.household_id, auth.uid(), 'member', 'active')
  on conflict (household_id, user_id) do update set status = 'active';
  update public.household_invites
  set consumed_by = auth.uid(), consumed_at = now()
  where id = v_invite.id;
  return v_invite.household_id;
end;
$$;
revoke all on function public.accept_household_invite(text) from public;
grant execute on function public.accept_household_invite(text) to authenticated;

create policy "Members view their households" on public.households
  for select to authenticated using (public.is_household_member(id));
create policy "Owners create households" on public.households
  for insert to authenticated with check (owner_id = auth.uid());
create policy "Owners update households" on public.households
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "Members view own memberships" on public.household_memberships
  for select to authenticated using (
    user_id = auth.uid() or exists (
      select 1 from public.households h where h.id = household_id and h.owner_id = auth.uid()
    )
  );
create policy "Owners manage memberships" on public.household_memberships
  for all to authenticated using (exists (
    select 1 from public.households h where h.id = household_id and h.owner_id = auth.uid()
  )) with check (exists (
    select 1 from public.households h where h.id = household_id and h.owner_id = auth.uid()
  ));
create policy "Members manage shared expenses" on public.household_shared_expenses
  for all to authenticated using (public.is_household_member(household_id)) with check (
    created_by = auth.uid() and public.is_household_member(household_id)
  );

grant select, insert, update, delete on
  public.profiles, public.financial_profiles, public.accounts,
  public.account_balance_snapshots, public.bank_connections,
  public.account_aggregator_consents, public.connection_sync_events,
  public.expense_boards,
  public.budget_allocations, public.transactions, public.commitments,
  public.savings_goals, public.savings_contributions, public.subscriptions,
  public.households, public.household_memberships, public.household_shared_expenses
to authenticated;
grant select on public.catalog_items, public.catalog_aliases to authenticated;
