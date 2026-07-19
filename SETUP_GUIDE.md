# EduPulse Setup Guide

## 1. Database setup (fresh Supabase project)

1. Create your 13 base tables (users, roles, students, parents, student_parents,
   staff, classes, subjects, class_subject_teachers, attendance_registers,
   student_attendance, fee_invoices, fee_payments) per your original schema.
2. Open Supabase → SQL Editor → New Query, paste the entire contents of
   **`edupulse_complete_setup.sql`**, and run it. This one file sets up
   everything else: auth linking, all Row Level Security policies, the
   Exams/Timetable/Announcements/Documents/Academic Terms/Audit Log modules,
   the full Admin/Teacher/Accountant/Staff/Parent/Student role model,
   teacher class-locking, school branding, and notification read-tracking.
   It's safe to re-run this file if you're ever unsure what state your
   database is in — every statement is idempotent.
3. In Supabase → Authentication → Providers, make sure **Email** is enabled.
   While testing, you can turn off "Confirm email" under Authentication →
   Settings so sign-up logs people in immediately (turn it back on before
   real users start signing up).
4. **For password reset emails to actually send**, Supabase's default email
   sender is rate-limited and not meant for production. Once you have real
   users, set up a custom SMTP provider under Authentication → Settings →
   SMTP Settings (Resend, Postmark, SendGrid, etc. all work).

## 2. Bootstrap your first Admin account

Supabase Auth accounts and EduPulse profiles are separate — the app links
them by matching email. To create the very first Admin (no admin exists
yet to add one through the UI), edit and run **`create_admin.sql`**:

```sql
insert into public.users (full_name, email, phone_number, is_active, role_id)
values (
  'Your Full Name',
  '[email protected]',
  '0000000000',
  true,
  (select id from public.roles where role_name = 'Admin')
);
```

Then open the app → **Sign Up** tab → same email → choose a password.
The database trigger links your new login to that profile automatically.

## 3. Adding everyone else

Nobody else needs manual SQL. From the app, as Admin:

- **Staff & Teachers → Add Staff** — choose an Access Level:
  - **Teacher** — manages Attendance, Exams & Results (only for classes
    they're assigned to via Classes & Subjects → Assign Teacher)
  - **Accountant** — manages Fees & Payments only
  - **Staff** — manages Documents & Announcements only (the legacy/general role)
- **Students → Add Student**
- **Parent Portal → Add Parent**, then **Link to Student** to connect them
  to their child(ren)

Each person then goes to **Sign Up** with the *same email* you used to
register them, and picks their own password — this activates their account
and links it to the profile you created.

## 4. Deploying the app itself

- `index.html` is the entire app — host it anywhere that serves static
  files (Netlify, Vercel, GitHub Pages, or your own web server).
- Upload **`manifest.json`** to the *same folder* as `index.html` — it
  enables "Add to Home Screen" on phones. Replace the placeholder icon in
  it with a real logo file when you have one.
- Your Supabase URL and anon key are already embedded in `index.html`
  (the anon key is meant to be public — it's safe to ship in client code,
  since Row Level Security is what actually protects your data).

## 5. School branding (white-labeling)

Log in as Admin → **Settings → School Branding** to set your school's
name, logo (an image URL), brand color, and currency symbol. This updates
the login screen, sidebar, and every currency display across the app —
no code changes needed. Useful if you're selling this to multiple schools:
each school gets its own Supabase project + its own copy of `index.html`,
and each can set their own branding independently.

## 6. Backups

Supabase's free tier has no automatic backups. Go to **Settings → Data
Backup** periodically (weekly is reasonable for a small school) and click
**Export All Data** — it downloads a full JSON snapshot of every table.
Keep these somewhere safe (cloud drive, external storage). There's no
one-click *restore* built yet — treat this as insurance, not a live backup
system, and loop me in if you want a restore flow built too.

## 7. Known limitations (see the earlier conversation for full detail)

- Free-tier Supabase projects pause after 7 days of inactivity — the app
  will be unreachable until manually un-paused from the Supabase dashboard.
- No automatic backups on free tier — use the Data Backup export above.
- Single-tenant: one Supabase project per school. Selling to multiple
  schools means a separate project (and separate copy of the SQL + HTML)
  per school, not one shared multi-school database.
- WhatsApp report card delivery is manual (native share sheet), not fully
  automated — see `whatsapp_api_setup_guide.md` for the path to full
  automation via the WhatsApp Business API.
