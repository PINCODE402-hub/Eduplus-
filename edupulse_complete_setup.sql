-- =========================================================
-- EDUPULSE — COMPLETE DATABASE SETUP (all-in-one)
-- Run this ONCE in a fresh Supabase project's SQL Editor,
-- top to bottom. It replaces the need to run separate
-- migration files individually.
--
-- Prerequisite: you've already created the 13 base tables from
-- your original EDUPULSE DATABASE SCHEMA (users, roles, students,
-- parents, student_parents, staff, classes, subjects,
-- class_subject_teachers, attendance_registers, student_attendance,
-- fee_invoices, fee_payments) before running this file.
--
-- This file is organized in four parts:
--   PART 1 — Auth linking, RLS foundation
--   PART 2 — New modules: exams, timetable, announcements, documents,
--            academic terms, audit log
--   PART 3 — Final role model: Admin/Teacher/Accountant/Staff/Parent/
--            Student permissions, incl. the users-table read-access fix
--   PART 4 — Teacher class-locking (a Teacher can only manage
--            Attendance/Exams for classes they're actually assigned to)
--            + school branding settings (name/logo/color, editable
--            from Settings by Admin)
-- =========================================================

-- =========================================================
-- PART 1 — AUTH, RLS FOUNDATION
-- =========================================================

-- =========================================================
-- EDUPULSE SCHEMA UPDATES: new tables, auth linking, RLS
-- Run this ONCE in Supabase Dashboard -> SQL Editor -> New query
-- =========================================================

-- ---------------------------------------------------------
-- 0. SEED ROLES (safe if they already exist)
-- ---------------------------------------------------------
insert into public.roles (role_name, description)
select v.role_name, v.description
from (values
  ('Admin', 'Full system access'),
  ('Staff', 'Teachers and general staff'),
  ('Parent', 'Parent / guardian portal access'),
  ('Student', 'Student self-service access')
) as v(role_name, description)
where not exists (select 1 from public.roles r where r.role_name = v.role_name);

-- ---------------------------------------------------------
-- 1. NEW TABLES (not in original schema, needed for the
--    Exams, Timetable, Announcements and Documents modules)
-- ---------------------------------------------------------

-- NOTE ON TYPES: students.id / staff.id / parents.id / users.id are UUID in
-- this project; classes.id / subjects.id are integer. Foreign keys below
-- match each column to the actual type of the table it references.

create table if not exists public.exams (
  id bigint generated always as identity primary key,
  class_id bigint references public.classes(id) on delete cascade,
  subject_id bigint references public.subjects(id) on delete cascade,
  exam_name text not null,
  academic_term text,
  exam_date date,
  max_marks numeric not null default 100,
  created_by uuid references public.staff(id),
  created_at timestamptz not null default now()
);

create table if not exists public.exam_results (
  id bigint generated always as identity primary key,
  exam_id bigint references public.exams(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade,
  marks_obtained numeric,
  grade text,
  remarks text,
  recorded_by uuid references public.staff(id),
  created_at timestamptz not null default now(),
  unique (exam_id, student_id)
);

create table if not exists public.timetable_slots (
  id bigint generated always as identity primary key,
  class_id bigint references public.classes(id) on delete cascade,
  subject_id bigint references public.subjects(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete set null,
  day_of_week smallint not null check (day_of_week between 1 and 7), -- 1=Mon..7=Sun
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id bigint generated always as identity primary key,
  title text not null,
  content text not null,
  target_role text not null default 'All', -- 'All' | 'Staff' | 'Parent' | 'Student'
  class_id bigint references public.classes(id) on delete set null, -- optional: scope to one class
  posted_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.documents (
  id bigint generated always as identity primary key,
  title text not null,
  category text default 'General',
  file_path text not null, -- path inside the 'documents' storage bucket
  student_id uuid references public.students(id) on delete cascade, -- optional link to a student
  uploaded_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

-- Storage bucket for the Documents module (private; access via signed URLs)
insert into storage.buckets (id, name, public)
select 'documents', 'documents', false
where not exists (select 1 from storage.buckets where id = 'documents');

-- ---------------------------------------------------------
-- 2. HELPER FUNCTIONS (used by RLS policies below)
-- ---------------------------------------------------------

create or replace function public.current_app_user_id()
returns uuid
language sql stable security definer
as $$
  select id from public.users where auth_id = auth.uid()
$$;

create or replace function public.current_role_name()
returns text
language sql stable security definer
as $$
  select r.role_name
  from public.users u
  join public.roles r on r.id = u.role_id
  where u.auth_id = auth.uid()
$$;

create or replace function public.current_staff_id()
returns uuid
language sql stable security definer
as $$
  select s.id from public.staff s
  join public.users u on u.id = s.user_id
  where u.auth_id = auth.uid()
$$;

create or replace function public.current_student_id()
returns uuid
language sql stable security definer
as $$
  select st.id from public.students st
  join public.users u on u.id = st.user_id
  where u.auth_id = auth.uid()
$$;

create or replace function public.current_parent_id()
returns uuid
language sql stable security definer
as $$
  select p.id from public.parents p
  join public.users u on u.id = p.user_id
  where u.auth_id = auth.uid()
$$;

create or replace function public.is_admin_or_staff()
returns boolean
language sql stable security definer
as $$
  select public.current_role_name() in ('Admin', 'Staff')
$$;

-- ---------------------------------------------------------
-- 3. AUTH LINKING TRIGGER
--    Flow: Admin creates the person's profile row in public.users
--    first (no auth_id yet, via the app's Add Student/Staff/Parent
--    forms). The person then signs up on the login page using the
--    SAME email address. This trigger links their new auth.users.id
--    to the existing public.users row automatically.
-- ---------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql security definer
as $$
begin
  update public.users
  set auth_id = new.id
  where lower(email) = lower(new.email) and auth_id is null;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------
-- 4. ENABLE ROW LEVEL SECURITY ON ALL TABLES
-- ---------------------------------------------------------
alter table public.users enable row level security;
alter table public.roles enable row level security;
alter table public.students enable row level security;
alter table public.parents enable row level security;
alter table public.student_parents enable row level security;
alter table public.staff enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.class_subject_teachers enable row level security;
alter table public.attendance_registers enable row level security;
alter table public.student_attendance enable row level security;
alter table public.fee_invoices enable row level security;
alter table public.fee_payments enable row level security;
alter table public.exams enable row level security;
alter table public.exam_results enable row level security;
alter table public.timetable_slots enable row level security;
alter table public.announcements enable row level security;
alter table public.documents enable row level security;

-- ---------------------------------------------------------
-- 5. POLICIES
--    Pattern: Admin/Staff = full access.
--    Parents = read-only access to their own linked children's data.
--    Students = read-only access to their own data.
-- ---------------------------------------------------------

-- ROLES (everyone signed in can read role names)
create policy "roles_read_all" on public.roles for select
  using (auth.uid() is not null);

-- USERS
create policy "users_admin_staff_all" on public.users for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "users_read_own" on public.users for select
  using (auth_id = auth.uid());

-- STUDENTS
create policy "students_admin_staff_all" on public.students for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "students_read_own" on public.students for select
  using (id = public.current_student_id());
create policy "students_read_by_parent" on public.students for select
  using (id in (
    select sp.student_id from public.student_parents sp
    where sp.parent_id = public.current_parent_id()
  ));

-- PARENTS
create policy "parents_admin_staff_all" on public.parents for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "parents_read_own" on public.parents for select
  using (id = public.current_parent_id());

-- STUDENT_PARENTS
create policy "student_parents_admin_staff_all" on public.student_parents for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "student_parents_read_own" on public.student_parents for select
  using (parent_id = public.current_parent_id() or student_id = public.current_student_id());

-- STAFF (directory info is not sensitive; all signed-in users can read, only admin/staff write)
create policy "staff_read_all" on public.staff for select
  using (auth.uid() is not null);
create policy "staff_admin_staff_write" on public.staff for insert
  with check (public.is_admin_or_staff());
create policy "staff_admin_staff_update" on public.staff for update
  using (public.is_admin_or_staff());
create policy "staff_admin_staff_delete" on public.staff for delete
  using (public.is_admin_or_staff());

-- CLASSES / SUBJECTS / CLASS_SUBJECT_TEACHERS (read for all signed in, write for admin/staff)
create policy "classes_read_all" on public.classes for select using (auth.uid() is not null);
create policy "classes_write" on public.classes for insert with check (public.is_admin_or_staff());
create policy "classes_update" on public.classes for update using (public.is_admin_or_staff());
create policy "classes_delete" on public.classes for delete using (public.is_admin_or_staff());

create policy "subjects_read_all" on public.subjects for select using (auth.uid() is not null);
create policy "subjects_write" on public.subjects for insert with check (public.is_admin_or_staff());
create policy "subjects_update" on public.subjects for update using (public.is_admin_or_staff());
create policy "subjects_delete" on public.subjects for delete using (public.is_admin_or_staff());

create policy "cst_read_all" on public.class_subject_teachers for select using (auth.uid() is not null);
create policy "cst_write" on public.class_subject_teachers for insert with check (public.is_admin_or_staff());
create policy "cst_update" on public.class_subject_teachers for update using (public.is_admin_or_staff());
create policy "cst_delete" on public.class_subject_teachers for delete using (public.is_admin_or_staff());

-- ATTENDANCE
create policy "att_reg_admin_staff_all" on public.attendance_registers for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());

create policy "student_att_admin_staff_all" on public.student_attendance for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "student_att_read_own" on public.student_attendance for select
  using (student_id = public.current_student_id());
create policy "student_att_read_by_parent" on public.student_attendance for select
  using (student_id in (
    select sp.student_id from public.student_parents sp
    where sp.parent_id = public.current_parent_id()
  ));

-- FEES
create policy "fee_invoices_admin_staff_all" on public.fee_invoices for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "fee_invoices_read_own" on public.fee_invoices for select
  using (student_id = public.current_student_id());
create policy "fee_invoices_read_by_parent" on public.fee_invoices for select
  using (student_id in (
    select sp.student_id from public.student_parents sp
    where sp.parent_id = public.current_parent_id()
  ));

create policy "fee_payments_admin_staff_all" on public.fee_payments for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "fee_payments_read_own" on public.fee_payments for select
  using (invoice_id in (select id from public.fee_invoices where student_id = public.current_student_id()));
create policy "fee_payments_read_by_parent" on public.fee_payments for select
  using (invoice_id in (
    select id from public.fee_invoices where student_id in (
      select sp.student_id from public.student_parents sp
      where sp.parent_id = public.current_parent_id()
    )
  ));

-- EXAMS / RESULTS
create policy "exams_admin_staff_all" on public.exams for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "exams_read_all_signed_in" on public.exams for select using (auth.uid() is not null);

create policy "exam_results_admin_staff_all" on public.exam_results for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "exam_results_read_own" on public.exam_results for select
  using (student_id = public.current_student_id());
create policy "exam_results_read_by_parent" on public.exam_results for select
  using (student_id in (
    select sp.student_id from public.student_parents sp
    where sp.parent_id = public.current_parent_id()
  ));

-- TIMETABLE (read for all signed in, write admin/staff)
create policy "timetable_read_all" on public.timetable_slots for select using (auth.uid() is not null);
create policy "timetable_write" on public.timetable_slots for insert with check (public.is_admin_or_staff());
create policy "timetable_update" on public.timetable_slots for update using (public.is_admin_or_staff());
create policy "timetable_delete" on public.timetable_slots for delete using (public.is_admin_or_staff());

-- ANNOUNCEMENTS (read for all signed in, write admin/staff)
create policy "announcements_read_all" on public.announcements for select using (auth.uid() is not null);
create policy "announcements_write" on public.announcements for insert with check (public.is_admin_or_staff());
create policy "announcements_update" on public.announcements for update using (public.is_admin_or_staff());
create policy "announcements_delete" on public.announcements for delete using (public.is_admin_or_staff());

-- DOCUMENTS
create policy "documents_admin_staff_all" on public.documents for all
  using (public.is_admin_or_staff()) with check (public.is_admin_or_staff());
create policy "documents_read_own" on public.documents for select
  using (student_id = public.current_student_id());
create policy "documents_read_by_parent" on public.documents for select
  using (student_id in (
    select sp.student_id from public.student_parents sp
    where sp.parent_id = public.current_parent_id()
  ));

-- STORAGE POLICIES for the 'documents' bucket
create policy "documents_bucket_admin_staff_all" on storage.objects for all
  using (bucket_id = 'documents' and public.is_admin_or_staff())
  with check (bucket_id = 'documents' and public.is_admin_or_staff());
create policy "documents_bucket_read_signed_in" on storage.objects for select
  using (bucket_id = 'documents' and auth.uid() is not null);

-- =========================================================
-- DONE. Next steps:
-- 1. Run this whole file in Supabase SQL Editor.
-- 2. In Supabase Dashboard -> Authentication -> Providers, make sure
--    Email provider is enabled.
-- 3. In Authentication -> Settings, you can disable "Confirm email"
--    while testing so signup logs the user in immediately.
-- =========================================================
-- =========================================================
-- PART 2 — EXAMS, TIMETABLE, ANNOUNCEMENTS, DOCUMENTS, TERMS, AUDIT LOG
-- =========================================================

-- =========================================================
-- EDUPULSE PRO UPGRADES: academic terms + audit log
-- Run this ONCE in Supabase SQL Editor, after the earlier migration.
-- =========================================================

-- ---------------------------------------------------------
-- 1. ACADEMIC TERMS
-- ---------------------------------------------------------
create table if not exists public.academic_terms (
  id bigint generated always as identity primary key,
  term_name text not null unique,
  start_date date,
  end_date date,
  is_current boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.academic_terms enable row level security;

create policy "terms_read_all" on public.academic_terms for select using (auth.uid() is not null);
create policy "terms_write" on public.academic_terms for insert with check (public.is_admin_or_staff());
create policy "terms_update" on public.academic_terms for update using (public.is_admin_or_staff());
create policy "terms_delete" on public.academic_terms for delete using (public.is_admin_or_staff());

-- ---------------------------------------------------------
-- 2. AUDIT LOG
--    Generic trigger: logs every insert/update/delete on the
--    tables it's attached to. record_id is stored as text so it
--    works whether the source table's id is uuid or bigint.
-- ---------------------------------------------------------
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  operation text not null,
  record_id text,
  changed_by uuid references public.users(id),
  changed_at timestamptz not null default now(),
  old_data jsonb,
  new_data jsonb
);

alter table public.audit_log enable row level security;
create policy "audit_log_admin_staff_read" on public.audit_log for select
  using (public.is_admin_or_staff());
-- No insert/update/delete policies for regular roles: only the trigger
-- (running as the table owner, which bypasses RLS) can write here.

create or replace function public.audit_trigger_fn()
returns trigger
language plpgsql security definer
as $$
declare
  actor uuid;
begin
  actor := public.current_app_user_id();
  if (TG_OP = 'DELETE') then
    insert into public.audit_log(table_name, operation, record_id, changed_by, old_data)
    values (TG_TABLE_NAME, TG_OP, OLD.id::text, actor, to_jsonb(OLD));
    return OLD;
  elsif (TG_OP = 'UPDATE') then
    insert into public.audit_log(table_name, operation, record_id, changed_by, old_data, new_data)
    values (TG_TABLE_NAME, TG_OP, NEW.id::text, actor, to_jsonb(OLD), to_jsonb(NEW));
    return NEW;
  else
    insert into public.audit_log(table_name, operation, record_id, changed_by, new_data)
    values (TG_TABLE_NAME, TG_OP, NEW.id::text, actor, to_jsonb(NEW));
    return NEW;
  end if;
end;
$$;

-- Attach to the most sensitive/high-value tables. Add more later with the
-- same pattern if you want broader coverage.
drop trigger if exists audit_students on public.students;
create trigger audit_students after insert or update or delete on public.students
  for each row execute function public.audit_trigger_fn();

drop trigger if exists audit_staff on public.staff;
create trigger audit_staff after insert or update or delete on public.staff
  for each row execute function public.audit_trigger_fn();

drop trigger if exists audit_fee_invoices on public.fee_invoices;
create trigger audit_fee_invoices after insert or update or delete on public.fee_invoices
  for each row execute function public.audit_trigger_fn();

drop trigger if exists audit_fee_payments on public.fee_payments;
create trigger audit_fee_payments after insert or update or delete on public.fee_payments
  for each row execute function public.audit_trigger_fn();

drop trigger if exists audit_exam_results on public.exam_results;
create trigger audit_exam_results after insert or update or delete on public.exam_results
  for each row execute function public.audit_trigger_fn();

drop trigger if exists audit_student_attendance on public.student_attendance;
create trigger audit_student_attendance after insert or update or delete on public.student_attendance
  for each row execute function public.audit_trigger_fn();

-- =========================================================
-- DONE. This adds:
--  - academic_terms table (manage from Settings in the app)
--  - audit_log table, auto-populated on changes to students, staff,
--    fee_invoices, fee_payments, exam_results, student_attendance
--    (viewable from Settings > Audit Log, Admin/Staff only)
-- =========================================================
-- =========================================================
-- PART 3 — FINAL ROLE MODEL (Admin/Teacher/Accountant/Staff/Parent/Student)
-- =========================================================

-- =========================================================
-- EDUPULSE FINAL ROLE MODEL (run this instead of, or after, any
-- of: edupulse_accountant_role.sql, edupulse_roles_upgrade.sql,
-- edupulse_v2_upgrades.sql — this file supersedes all three and
-- is safe to run whether or not you ran any of them already.)
--
-- Run this ONCE in Supabase SQL Editor, after edupulse_schema_updates.sql
-- and edupulse_pro_upgrades.sql.
--
-- FINAL ROLE MODEL:
--   Admin      — full access to everything
--   Teacher    — manages Attendance, Exams & Results; read-only elsewhere
--   Accountant — manages Fees & Payments; read-only elsewhere
--   Staff      — legacy/general role: manages Documents & Announcements,
--                read-only elsewhere (no attendance/exam/fee access)
--   Parent     — read-only, own linked children only
--   Student    — read-only, own records only
--
-- IMPORTANT: if you already added staff members under the old model
-- (where "Staff" meant full access), open Staff & Teachers in the app
-- and use "Edit Staff" to reassign each one to Teacher or Accountant
-- as appropriate — otherwise they'll lose access to attendance/exams/fees.
-- =========================================================

-- ---------------------------------------------------------
-- 1. SEED ROLES (safe if they already exist)
-- ---------------------------------------------------------
insert into public.roles (role_name, description)
select v.role_name, v.description
from (values
  ('Admin', 'Full system access'),
  ('Staff', 'General staff: documents & announcements'),
  ('Teacher', 'Manages attendance, exams and results for their classes'),
  ('Accountant', 'Manages fee invoices and payments'),
  ('Parent', 'Parent / guardian portal access'),
  ('Student', 'Student self-service access')
) as v(role_name, description)
where not exists (select 1 from public.roles r where r.role_name = v.role_name);

-- ---------------------------------------------------------
-- 2. HELPER FUNCTIONS (create or replace — safe to re-run)
-- ---------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer as $$
  select public.current_role_name() = 'Admin'
$$;

create or replace function public.is_academic_staff()
returns boolean language sql stable security definer as $$
  select public.current_role_name() in ('Admin', 'Teacher')
$$;

create or replace function public.is_finance_staff()
returns boolean language sql stable security definer as $$
  select public.current_role_name() in ('Admin', 'Accountant')
$$;

create or replace function public.is_staff_level()
returns boolean language sql stable security definer as $$
  select public.current_role_name() in ('Admin', 'Teacher', 'Accountant', 'Staff')
$$;

-- ---------------------------------------------------------
-- 3. DROP EVERY POLICY NAME EVER USED BY ANY PRIOR MIGRATION
--    (idempotent regardless of migration history)
-- ---------------------------------------------------------
drop policy if exists "users_admin_staff_all" on public.users;
drop policy if exists "users_admin_all" on public.users;
drop policy if exists "users_read_all_signed_in" on public.users;

drop policy if exists "students_admin_staff_all" on public.students;
drop policy if exists "students_staff_read" on public.students;
drop policy if exists "students_admin_insert" on public.students;
drop policy if exists "students_admin_update" on public.students;
drop policy if exists "students_admin_delete" on public.students;
drop policy if exists "students_read_by_accountant" on public.students;
drop policy if exists "students_read_finance" on public.students;

drop policy if exists "parents_admin_staff_all" on public.parents;
drop policy if exists "parents_admin_all" on public.parents;

drop policy if exists "student_parents_admin_staff_all" on public.student_parents;
drop policy if exists "student_parents_admin_all" on public.student_parents;

drop policy if exists "staff_admin_staff_write" on public.staff;
drop policy if exists "staff_admin_staff_update" on public.staff;
drop policy if exists "staff_admin_staff_delete" on public.staff;
drop policy if exists "staff_admin_insert" on public.staff;
drop policy if exists "staff_admin_update" on public.staff;
drop policy if exists "staff_admin_delete" on public.staff;

drop policy if exists "classes_write" on public.classes;
drop policy if exists "classes_update" on public.classes;
drop policy if exists "classes_delete" on public.classes;
drop policy if exists "classes_admin_insert" on public.classes;
drop policy if exists "classes_admin_update" on public.classes;
drop policy if exists "classes_admin_delete" on public.classes;

drop policy if exists "subjects_write" on public.subjects;
drop policy if exists "subjects_update" on public.subjects;
drop policy if exists "subjects_delete" on public.subjects;
drop policy if exists "subjects_admin_insert" on public.subjects;
drop policy if exists "subjects_admin_update" on public.subjects;
drop policy if exists "subjects_admin_delete" on public.subjects;

drop policy if exists "cst_write" on public.class_subject_teachers;
drop policy if exists "cst_update" on public.class_subject_teachers;
drop policy if exists "cst_delete" on public.class_subject_teachers;
drop policy if exists "cst_admin_insert" on public.class_subject_teachers;
drop policy if exists "cst_admin_update" on public.class_subject_teachers;
drop policy if exists "cst_admin_delete" on public.class_subject_teachers;

drop policy if exists "att_reg_admin_staff_all" on public.attendance_registers;
drop policy if exists "att_reg_academic_all" on public.attendance_registers;

drop policy if exists "student_att_admin_staff_all" on public.student_attendance;
drop policy if exists "student_att_academic_all" on public.student_attendance;

drop policy if exists "exams_admin_staff_all" on public.exams;
drop policy if exists "exams_academic_all" on public.exams;

drop policy if exists "exam_results_admin_staff_all" on public.exam_results;
drop policy if exists "exam_results_academic_all" on public.exam_results;

drop policy if exists "fee_invoices_admin_staff_all" on public.fee_invoices;
drop policy if exists "fee_invoices_finance_all" on public.fee_invoices;
drop policy if exists "fee_invoices_accountant_all" on public.fee_invoices;
drop policy if exists "fee_invoices_staff_read" on public.fee_invoices;

drop policy if exists "fee_payments_admin_staff_all" on public.fee_payments;
drop policy if exists "fee_payments_finance_all" on public.fee_payments;
drop policy if exists "fee_payments_accountant_all" on public.fee_payments;
drop policy if exists "fee_payments_staff_read" on public.fee_payments;

drop policy if exists "timetable_write" on public.timetable_slots;
drop policy if exists "timetable_update" on public.timetable_slots;
drop policy if exists "timetable_delete" on public.timetable_slots;
drop policy if exists "timetable_admin_insert" on public.timetable_slots;
drop policy if exists "timetable_admin_update" on public.timetable_slots;
drop policy if exists "timetable_admin_delete" on public.timetable_slots;

drop policy if exists "announcements_write" on public.announcements;
drop policy if exists "announcements_update" on public.announcements;
drop policy if exists "announcements_delete" on public.announcements;
drop policy if exists "announcements_staff_insert" on public.announcements;
drop policy if exists "announcements_staff_update" on public.announcements;
drop policy if exists "announcements_staff_delete" on public.announcements;

drop policy if exists "documents_admin_staff_all" on public.documents;
drop policy if exists "documents_staff_all" on public.documents;

drop policy if exists "documents_bucket_admin_staff_all" on storage.objects;
drop policy if exists "documents_bucket_staff_all" on storage.objects;

drop policy if exists "terms_write" on public.academic_terms;
drop policy if exists "terms_update" on public.academic_terms;
drop policy if exists "terms_delete" on public.academic_terms;
drop policy if exists "terms_admin_insert" on public.academic_terms;
drop policy if exists "terms_admin_update" on public.academic_terms;
drop policy if exists "terms_admin_delete" on public.academic_terms;

drop policy if exists "audit_log_admin_staff_read" on public.audit_log;
drop policy if exists "audit_log_admin_read" on public.audit_log;

-- ---------------------------------------------------------
-- 4. CREATE THE FINAL POLICY SET
-- ---------------------------------------------------------

-- USERS: only Admin manages profile records directly; everyone signed in
-- can read basic profile info (name/email/phone) — needed because every
-- list in the app (students, staff, parents, rosters) shows a person's
-- name via a nested join into this table.
create policy "users_admin_all" on public.users for all
  using (public.is_admin()) with check (public.is_admin());
create policy "users_read_all_signed_in" on public.users for select
  using (auth.uid() is not null);

-- STUDENTS: any staff-level employee can read; only Admin writes.
-- (Parent/Student's own read policies from the original migration are
-- untouched and still apply on top of this.)
create policy "students_staff_read" on public.students for select
  using (public.is_staff_level());
create policy "students_admin_insert" on public.students for insert
  with check (public.is_admin());
create policy "students_admin_update" on public.students for update
  using (public.is_admin());
create policy "students_admin_delete" on public.students for delete
  using (public.is_admin());

-- PARENTS / STUDENT_PARENTS: Admin only
create policy "parents_admin_all" on public.parents for all
  using (public.is_admin()) with check (public.is_admin());
create policy "student_parents_admin_all" on public.student_parents for all
  using (public.is_admin()) with check (public.is_admin());

-- STAFF: everyone signed in can read the directory (unchanged from the
-- original migration's staff_read_all policy); only Admin writes.
create policy "staff_admin_insert" on public.staff for insert with check (public.is_admin());
create policy "staff_admin_update" on public.staff for update using (public.is_admin());
create policy "staff_admin_delete" on public.staff for delete using (public.is_admin());

-- CLASSES / SUBJECTS / CLASS_SUBJECT_TEACHERS: Admin manages, all can read
create policy "classes_admin_insert" on public.classes for insert with check (public.is_admin());
create policy "classes_admin_update" on public.classes for update using (public.is_admin());
create policy "classes_admin_delete" on public.classes for delete using (public.is_admin());

create policy "subjects_admin_insert" on public.subjects for insert with check (public.is_admin());
create policy "subjects_admin_update" on public.subjects for update using (public.is_admin());
create policy "subjects_admin_delete" on public.subjects for delete using (public.is_admin());

create policy "cst_admin_insert" on public.class_subject_teachers for insert with check (public.is_admin());
create policy "cst_admin_update" on public.class_subject_teachers for update using (public.is_admin());
create policy "cst_admin_delete" on public.class_subject_teachers for delete using (public.is_admin());

-- ATTENDANCE: Admin + Teacher only
create policy "att_reg_academic_all" on public.attendance_registers for all
  using (public.is_academic_staff()) with check (public.is_academic_staff());
create policy "student_att_academic_all" on public.student_attendance for all
  using (public.is_academic_staff()) with check (public.is_academic_staff());

-- EXAMS / RESULTS: Admin + Teacher only
create policy "exams_academic_all" on public.exams for all
  using (public.is_academic_staff()) with check (public.is_academic_staff());
create policy "exam_results_academic_all" on public.exam_results for all
  using (public.is_academic_staff()) with check (public.is_academic_staff());

-- FEES: Admin + Accountant only
-- (Parent/Student's own read policies from the original migration are
-- untouched and still apply on top of this.)
create policy "fee_invoices_finance_all" on public.fee_invoices for all
  using (public.is_finance_staff()) with check (public.is_finance_staff());
create policy "fee_payments_finance_all" on public.fee_payments for all
  using (public.is_finance_staff()) with check (public.is_finance_staff());

-- TIMETABLE: Admin only manages, everyone can read
create policy "timetable_admin_insert" on public.timetable_slots for insert with check (public.is_admin());
create policy "timetable_admin_update" on public.timetable_slots for update using (public.is_admin());
create policy "timetable_admin_delete" on public.timetable_slots for delete using (public.is_admin());

-- ANNOUNCEMENTS: any staff-level employee (Admin/Teacher/Accountant/Staff) can post
create policy "announcements_staff_insert" on public.announcements for insert with check (public.is_staff_level());
create policy "announcements_staff_update" on public.announcements for update using (public.is_staff_level());
create policy "announcements_staff_delete" on public.announcements for delete using (public.is_staff_level());

-- DOCUMENTS: any staff-level employee can manage
create policy "documents_staff_all" on public.documents for all
  using (public.is_staff_level()) with check (public.is_staff_level());
create policy "documents_bucket_staff_all" on storage.objects for all
  using (bucket_id = 'documents' and public.is_staff_level())
  with check (bucket_id = 'documents' and public.is_staff_level());

-- ACADEMIC TERMS: Admin only
create policy "terms_admin_insert" on public.academic_terms for insert with check (public.is_admin());
create policy "terms_admin_update" on public.academic_terms for update using (public.is_admin());
create policy "terms_admin_delete" on public.academic_terms for delete using (public.is_admin());

-- AUDIT LOG: Admin only
create policy "audit_log_admin_read" on public.audit_log for select using (public.is_admin());

-- ---------------------------------------------------------
-- 5. NOTIFICATION READ-TRACKING (the table the app actually uses)
-- ---------------------------------------------------------
create table if not exists public.notification_dismissals (
  user_id uuid references public.users(id) on delete cascade,
  notification_key text not null,
  dismissed_at timestamptz not null default now(),
  primary key (user_id, notification_key)
);
alter table public.notification_dismissals enable row level security;
drop policy if exists "own_dismissals_all" on public.notification_dismissals;
create policy "own_dismissals_all" on public.notification_dismissals for all
  using (user_id = public.current_app_user_id())
  with check (user_id = public.current_app_user_id());

-- =========================================================
-- DONE. Next step: open Staff & Teachers in the app and use the
-- "Edit Staff" button to set each existing staff member's Access
-- Level to Teacher or Accountant as appropriate — the generic
-- "Staff" role now only manages Documents & Announcements.
-- =========================================================

-- =========================================================
-- PART 4 — TEACHER CLASS-LOCKING + SCHOOL BRANDING
-- =========================================================

-- ---------------------------------------------------------
-- 1. TEACHER CLASS-LOCKING
--    Previously any Teacher could manage Attendance/Exams for ANY
--    class. Now a Teacher can only manage a class's attendance/exams
--    if they're actually assigned to that class in
--    class_subject_teachers (as a teacher of any subject in it).
--    Admins are unaffected — they can still manage every class.
-- ---------------------------------------------------------
create or replace function public.is_teacher_of_class(p_class_id bigint)
returns boolean
language sql stable security definer
as $$
  select exists (
    select 1 from public.class_subject_teachers cst
    where cst.class_id = p_class_id and cst.staff_id = public.current_staff_id()
  )
$$;

create or replace function public.can_manage_class_academic(p_class_id bigint)
returns boolean
language sql stable security definer
as $$
  select public.is_admin() or public.is_teacher_of_class(p_class_id)
$$;

drop policy if exists "att_reg_academic_all" on public.attendance_registers;
create policy "att_reg_academic_scoped" on public.attendance_registers for all
  using (public.can_manage_class_academic(class_id))
  with check (public.can_manage_class_academic(class_id));

drop policy if exists "student_att_academic_all" on public.student_attendance;
create policy "student_att_academic_scoped" on public.student_attendance for all
  using (register_id in (select id from public.attendance_registers where public.can_manage_class_academic(class_id)))
  with check (register_id in (select id from public.attendance_registers where public.can_manage_class_academic(class_id)));

drop policy if exists "exams_academic_all" on public.exams;
create policy "exams_academic_scoped" on public.exams for all
  using (public.can_manage_class_academic(class_id))
  with check (public.can_manage_class_academic(class_id));

drop policy if exists "exam_results_academic_all" on public.exam_results;
create policy "exam_results_academic_scoped" on public.exam_results for all
  using (exam_id in (select id from public.exams where public.can_manage_class_academic(class_id)))
  with check (exam_id in (select id from public.exams where public.can_manage_class_academic(class_id)));

-- Note: reading the student directory (students_staff_read) stays
-- unscoped — Teachers can still see the whole school's student list,
-- they just can't mark attendance or enter exam results for a class
-- they aren't assigned to teach.

-- ---------------------------------------------------------
-- 2. SCHOOL BRANDING SETTINGS (white-label: name, logo, color)
--    Single-row table — the app always reads/writes row id = 1.
-- ---------------------------------------------------------
create table if not exists public.school_settings (
  id bigint generated always as identity primary key,
  school_name text not null default 'EduPulse',
  logo_url text,
  primary_color text not null default '#3b82f6',
  currency_symbol text not null default '₵',
  updated_at timestamptz not null default now()
);

alter table public.school_settings enable row level security;
drop policy if exists "school_settings_read_all" on public.school_settings;
create policy "school_settings_read_all" on public.school_settings for select
  using (true); -- public read: school name/logo/color aren't sensitive, and the
                -- login screen (before anyone is signed in) needs to show them too
drop policy if exists "school_settings_admin_insert" on public.school_settings;
create policy "school_settings_admin_insert" on public.school_settings for insert
  with check (public.is_admin());
drop policy if exists "school_settings_admin_update" on public.school_settings;
create policy "school_settings_admin_update" on public.school_settings for update
  using (public.is_admin());

insert into public.school_settings (school_name)
select 'EduPulse' where not exists (select 1 from public.school_settings);

-- =========================================================
-- ALL DONE. Your database is fully set up: base schema + auth linking +
-- exams/timetable/announcements/documents/terms/audit log + the final
-- role model + teacher class-locking + school branding.
-- =========================================================

