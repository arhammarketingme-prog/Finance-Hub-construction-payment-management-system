# Finance Hub — Version 1

A mobile-first finance/payment tracker for a construction business, built as a static
HTML/JS site (no build step) backed by **Supabase** (database, auth, storage) and
deployed on **GitHub Pages**.

Covers: client receipts, supplier expenses, contractor payments, labour payments,
self expenses, site-wise filtering, GST tracking, attachments, Excel import
(4 approved sheets), reports (Excel/PDF export), user management, and audit history.

---

## 1. Set up Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Go to **SQL Editor** → paste the entire contents of `supabase/schema.sql` → **Run**.
   This creates all tables, indexes, RLS policies, the `attachments` storage bucket,
   and inserts the three initial sites (Zinnia, Whispering Grooves, Genial).
3. Go to **Authentication → Providers**:
   - **Email**: enabled by default. For OTP login, enable "Email OTP" under
     Authentication → Sign In / Providers → Email.
   - **Phone**: enable Phone auth and connect an SMS provider (Twilio, MessageBird, etc.)
     under Authentication → Providers → Phone. Without this, mobile OTP login will not work —
     email login still will.
4. Create your first Super Admin:
   - Authentication → Users → **Add user** (set an email + password).
   - Copy that user's UUID.
   - SQL Editor:
     ```sql
     insert into public.profiles (id, name, email, role, status)
     values ('<paste-uuid>', 'Your Name', 'you@example.com', 'super_admin', 'active');
     ```
5. Get your API keys: **Project Settings → API** → copy the **Project URL** and **anon public key**.

## 2. Connect the app to your project

Edit `assets/supabase-config.js`:

```js
window.SUPABASE_CONFIG = {
  url: "https://YOUR-PROJECT-REF.supabase.co",
  anonKey: "YOUR-PUBLIC-ANON-KEY"
};
```

The anon key is safe to expose in client code — it only grants what your Row Level
Security policies allow (see `supabase/schema.sql`).

## 3. Deploy to GitHub Pages

```bash
git init
git add .
git commit -m "Finance Hub v1"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

Then in the GitHub repo: **Settings → Pages → Build and deployment → Source: Deploy from a branch**,
select `main` and `/ (root)`. Your app will be live at
`https://<your-username>.github.io/<your-repo>/`.

## 4. Inviting new users (important)

Adding a user from the **Users** screen calls a Supabase **Edge Function** named
`invite-user`, because sending an invite requires Supabase's *service role* key —
which must never be placed in client-side code. Deploy it once:

```bash
supabase functions new invite-user
```

Replace its body with something like:

```ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const { email, name, role, mobile, sites } = await req.json()
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email)
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 })

  await admin.from('profiles').insert({
    id: data.user.id, name, email, mobile, role, status: 'active'
  })
  if (sites?.length) {
    await admin.from('user_site_access').insert(sites.map((site_id: string) => ({ user_id: data.user.id, site_id })))
  }
  return new Response(JSON.stringify({ userId: data.user.id }), { status: 200 })
})
```

```bash
supabase functions deploy invite-user
```

The invited user receives an email to set their password, then logs in normally
(password or OTP, per your Auth settings).

## 5. Importing historical Excel data

Open **Import** in the app and select your workbook. Only these sheets are read:

- `Expense Zinnia`
- `Expense Whispering Grooves` (also matches "Whispering grooves")
- `Expense Genial`
- `Ankit Self Expenses` (also matches "Ankit self Expenses")

Everything else (Weekly Payment Sheet, Sheet1, Tiles, etc.) is ignored automatically.

**Important — review before confirming:** the "Ankit Self Expenses" sheet mixes three
site sections (Genial / Zinnia / Whispering Grooves) in one worksheet. The importer
detects these sections by scanning for the site name as a heading and reading the
Date / Amount / Type of Expense columns beneath or beside it. This works for most
common layouts, but **always check the Step 3 preview** before confirming — if a
section wasn't detected correctly, it's safer to split that sheet by hand and
re-import than to trust the heuristic blindly. The app never overwrites or invents
data; it flags anything it isn't sure about instead.

## 6. Project structure

```
finance-hub/
├── index.html                 Login
├── otp.html                   OTP verification
├── dashboard.html              Summary cards, quick actions, recent activity
├── client-payments.html        Client receipts + history
├── supplier-expenses.html      Supplier expense entries
├── contractor-payments.html    Contractor payment entries
├── labour-payments.html        Labour payment entries
├── self-expenses.html          Self expense entries
├── site-allocation.html        Pending allocation tracking
├── reports.html                Filterable report + Excel/PDF export
├── import.html                 Excel import wizard
├── users.html                  Super Admin user management
├── assets/
│   ├── style.css                Design system
│   ├── app.js                   Shared Supabase/auth/formatting helpers
│   └── supabase-config.js       Your project URL + anon key (edit this)
└── supabase/
    └── schema.sql                Full DB schema + RLS policies
```

## 7. What's intentionally NOT in Version 1

Per the project spec: no biometric login, no merging of the five transaction ledgers,
no hard deletes (soft-delete/archive only), and no modules beyond what's listed above.
The schema is built so Version 2 (new sites, new roles, new modules) doesn't require
restructuring existing tables.

## 8. Known limitations of this prototype

- Dashboard/report totals are computed client-side by summing fetched rows. Fine for
  the data volumes in Version 1; if you grow into tens of thousands of rows, move
  these sums into Postgres views or RPC functions for speed.
- The Ankit Self Expenses section-detection is a heuristic (see §5) — verify the
  import preview rather than assuming it's perfect on the first try.
- PDF export uses the browser's print dialog ("Save as PDF") rather than a generated
  PDF file, to keep the app dependency-free.
