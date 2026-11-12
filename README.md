# MADS

MADS is a Flutter personal finance companion with Supabase authentication, monthly expense boards, budgets, and a transaction ledger.

## Run the app

```sh
flutter pub get
flutter run
```

You can override the Supabase project settings at build time:

```sh
flutter run \
  --dart-define=MADS_SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=MADS_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

The publishable key is intended for client apps. Never put a Supabase service role key in Flutter.

## Enable cloud finance sync

Apply [the MADS finance migration](supabase/migrations/202611120001_mads_finance.sql) to the configured Supabase project from its SQL editor or with the Supabase CLI. It creates the finance tables, owner scoped Row Level Security policies, backend managed category and merchant catalog, and household sharing tables.

Until the migration is applied, MADS keeps financial data on the device and shows the sync state in **Profile → Data**. The app automatically migrates the prior `SharedPreferences` finance profile, board budgets, and recorded board expenses into the new local format. Once the database migration is live, the app syncs this data to the signed in user’s rows.

## Finance rules

- Money is stored in integer minor units (paise for INR).
- Budget allocations are plans. Saving an allocation is never blocked because other boards use more than the planned pool.
- Expenses and refunds are separate posted transactions. A purchase is saved even when it exceeds its board budget.
- Board details accept manual transactions and pasted bank CSV rows. CSVs need a description column and an amount, debit, or credit column; reference IDs are used for duplicate protection when present.
- The monthly planning pool is monthly income minus the savings target. Safe-to-spend starts from the balance snapshot and adjusts only for posted transactions dated after that snapshot; transactions on or before it are treated as already reflected. The savings target remains a goal, not savings already achieved, and is not deducted from the cash snapshot. The income-to-balance difference is never treated as spending. Legacy unpaid commitment values remain stored but are not collected or deducted by the current profile.
- The MEVORA conversation sends computed finance context through the authenticated `mevora-finance-chat` Supabase Edge Function. Configure `AI_CHAT_COMPLETIONS_URL`, `AI_API_KEY`, and `AI_MODEL` as Supabase function secrets and deploy the function. Provider credentials are never stored in the Flutter app. Until configured, the chat shows an unavailable message rather than generating a pretend response.
- Merchant and category icon keys are resolved by the Supabase catalog RPC. Merchant logo URLs can be managed in the catalog; unknown names use a safe category icon.
- Household spaces use one time invite codes and expose only expenses explicitly entered in the shared household ledger.

Automatic bank or UPI data connections are not configured. MADS currently supports manual transaction entry; Account Aggregator access requires separate eligibility, provider onboarding, and user consent.
