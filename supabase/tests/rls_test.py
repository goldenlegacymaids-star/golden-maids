"""Security tests for Golden Maids RLS policies.

Builds a fresh local database (Supabase stub + all migrations), then acts as
a guest, two customers, an admin, a super admin and a booking manager, and
checks what each can and cannot do.

Usage:  python3 supabase/tests/rls_test.py
"""
import pathlib
import sys
import uuid

import psycopg
from psycopg import errors

ROOT = pathlib.Path(__file__).resolve().parents[1]
DB = "gm_rls_test"
results = []


def admin_conn(dbname="postgres"):
    return psycopg.connect(dbname=dbname, host="/var/run/postgresql", autocommit=True)


def setup():
    with admin_conn() as c:
        c.execute(f"drop database if exists {DB}")
        c.execute(f"create database {DB}")
    with admin_conn(DB) as c:
        c.execute((ROOT / "tests" / "local_supabase_stub.sql").read_text())
        for f in sorted((ROOT / "migrations").glob("*.sql")):
            c.execute(f.read_text())
            print(f"  applied {f.name}")


def new_user(c, email, name):
    uid = str(uuid.uuid4())
    c.execute(
        "insert into auth.users (id, email, raw_user_meta_data) values (%s, %s, %s)",
        (uid, email, psycopg.types.json.Jsonb({"full_name": name})),
    )
    return uid


def as_user(c, uid):
    """Run following statements as an API user (None = guest)."""
    c.execute("reset role")
    c.execute("select set_config('request.jwt.claim.sub', %s, false)", (uid or "",))
    c.execute("set role anon" if uid is None else "set role authenticated")


def reset(c):
    c.execute("reset role")
    c.execute("select set_config('request.jwt.claim.sub', '', false)")


def check(name, fn):
    try:
        fn()
        results.append((True, name, ""))
    except AssertionError as e:
        import traceback
        results.append((False, name, str(e) or " | ".join(l.strip() for l in traceback.format_exc().strip().splitlines()[-4:-1])))
    except Exception as e:  # noqa: BLE001
        results.append((False, name, f"{type(e).__name__}: {e}"))


def expect_denied(c, sql, params=()):
    """Statement must fail with a permission / RLS error."""
    try:
        with c.transaction():
            c.execute(sql, params)
    except (errors.InsufficientPrivilege,) as e:
        return
    raise AssertionError(f"expected permission error, but it succeeded: {sql}")


def expect_violation(c, sql, params=()):
    try:
        with c.transaction():
            c.execute(sql, params)
    except (errors.CheckViolation, errors.InsufficientPrivilege) as e:
        return
    raise AssertionError(f"expected rejection, but it succeeded: {sql} {params}")


def one(c, sql, params=()):
    return c.execute(sql, params).fetchone()[0]


def main():
    print("Building local test database…")
    setup()
    c = admin_conn(DB)

    # --- users -------------------------------------------------------------
    alice = new_user(c, "alice@example.com", "Alice Customer")
    bob = new_user(c, "bob@example.com", "Bob Customer")
    sam = new_user(c, "sam@example.com", "Sam Super")
    ada = new_user(c, "ada@example.com", "Ada Admin")
    ben = new_user(c, "ben@example.com", "Ben Booking")
    c.execute("insert into public.user_roles (user_id, role_id) values (%s, 'super_admin')", (sam,))

    # --- sign-up trigger -----------------------------------------------------
    def signup_creates_profile_and_customer_role():
        assert one(c, "select full_name from public.profiles where id=%s", (alice,)) == "Alice Customer"
        assert one(c, "select count(*) from public.user_roles where user_id=%s and role_id='customer'", (alice,)) == 1
        assert one(c, "select count(*) from public.admin_audit_logs where entity_id=%s", (alice,)) == 0, \
            "automatic customer role should not be audit-logged"
    check("Sign-up creates profile + Customer role (not audit-logged)", signup_creates_profile_and_customer_role)

    def email_sync():
        c.execute("update auth.users set email='alice.new@example.com' where id=%s", (alice,))
        assert one(c, "select email from public.profiles where id=%s", (alice,)) == "alice.new@example.com"
    check("Email change in auth is copied to profile", email_sync)

    # --- guest ---------------------------------------------------------------
    def guest_blocked():
        as_user(c, None)
        try:
            for t in ["profiles", "user_roles", "roles", "addresses", "admin_audit_logs"]:
                expect_denied(c, f"select * from public.{t}")
        finally:
            reset(c)
    check("Guest cannot read any table", guest_blocked)

    def guest_health():
        as_user(c, None)
        try:
            assert one(c, "select public.health_check() ->> 'status'") == "ok"
        finally:
            reset(c)
    check("Guest can call health_check", guest_health)

    def guest_no_private():
        as_user(c, None)
        try:
            expect_denied(c, "select private.is_admin()")
        finally:
            reset(c)
    check("Guest cannot call private role functions", guest_no_private)

    # --- customer: profiles ----------------------------------------------------
    def customer_sees_only_self():
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.profiles") == 1
            assert one(c, "select count(*) from public.profiles where id=%s", (bob,)) == 0
        finally:
            reset(c)
    check("Customer sees only own profile", customer_sees_only_self)

    def customer_edits_name():
        as_user(c, alice)
        try:
            c.execute("update public.profiles set full_name='Alice A.' where id=%s", (alice,))
            assert one(c, "select full_name from public.profiles where id=%s", (alice,)) == "Alice A."
        finally:
            reset(c)
    check("Customer can edit own name", customer_edits_name)

    def customer_cannot_edit_email_or_others():
        as_user(c, alice)
        try:
            expect_denied(c, "update public.profiles set email='x@evil.com' where id=%s", (alice,))
            expect_denied(c, "update public.profiles set phone='0000' where id=%s", (alice,))
            c.execute("update public.profiles set full_name='Hacked' where id=%s", (bob,))
        finally:
            reset(c)
        assert one(c, "select full_name from public.profiles where id=%s", (bob,)) == "Bob Customer"
    check("Customer cannot edit email/phone or another profile", customer_cannot_edit_email_or_others)

    def customer_cannot_insert_delete_profiles():
        as_user(c, alice)
        try:
            expect_denied(c, "insert into public.profiles (id) values (gen_random_uuid())")
            expect_denied(c, "delete from public.profiles where id=%s", (alice,))
        finally:
            reset(c)
    check("Customer cannot create or delete profiles", customer_cannot_insert_delete_profiles)

    # --- customer: roles -------------------------------------------------------
    def customer_no_self_promotion():
        as_user(c, alice)
        try:
            for role in ["super_admin", "admin", "booking_manager"]:
                expect_denied(c, "insert into public.user_roles (user_id, role_id) values (%s, %s)", (alice, role))
            expect_denied(c, "update public.user_roles set role_id='admin' where user_id=%s", (alice,))
            assert one(c, "select count(*) from public.user_roles") == 1, "should see only own role"
        finally:
            reset(c)
        assert one(c, "select count(*) from public.user_roles where user_id=%s", (alice,)) == 1
    check("Customer cannot give themselves any role", customer_no_self_promotion)

    def customer_cannot_edit_roles_table():
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.roles") == 8
            expect_denied(c, "insert into public.roles (id, name) values ('hacker','Hacker')")
            expect_denied(c, "update public.roles set is_staff=true where id='customer'")
        finally:
            reset(c)
    check("Customer can read but not change the roles list", customer_cannot_edit_roles_table)

    def customer_no_audit():
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.admin_audit_logs") == 0
            expect_denied(c, "insert into public.admin_audit_logs (action, entity_type) values ('fake.entry','x')")
        finally:
            reset(c)
    check("Customer cannot read or write audit logs", customer_no_audit)

    # --- super admin / admin ------------------------------------------------
    def super_admin_grants_admin():
        as_user(c, sam)
        try:
            c.execute("insert into public.user_roles (user_id, role_id) values (%s, 'admin')", (ada,))
        finally:
            reset(c)
        assert one(c, "select granted_by::text from public.user_roles where user_id=%s and role_id='admin'", (ada,)) == sam
    check("Super admin can grant Admin (granted_by recorded)", super_admin_grants_admin)

    def admin_grants_staff_role():
        as_user(c, ada)
        try:
            c.execute("insert into public.user_roles (user_id, role_id) values (%s, 'booking_manager')", (ben,))
            assert one(c, "select count(*) from public.profiles") == 5, "admin should see all profiles"
        finally:
            reset(c)
    check("Admin can grant staff roles and view all profiles", admin_grants_staff_role)

    def admin_cannot_escalate():
        as_user(c, ada)
        try:
            expect_denied(c, "insert into public.user_roles (user_id, role_id) values (%s, 'super_admin')", (ada,))
            expect_denied(c, "insert into public.user_roles (user_id, role_id) values (%s, 'admin')", (bob,))
            c.execute("delete from public.user_roles where user_id=%s and role_id='super_admin'", (sam,))
            c.execute("delete from public.user_roles where user_id=%s and role_id='admin'", (ada,))
        finally:
            reset(c)
        assert one(c, "select count(*) from public.user_roles where user_id=%s and role_id='super_admin'", (sam,)) == 1
        assert one(c, "select count(*) from public.user_roles where user_id=%s and role_id='admin'", (ada,)) == 1
    check("Admin cannot grant/remove Admin or Super Admin, or remove own role", admin_cannot_escalate)

    def admin_cannot_forge_granted_by():
        as_user(c, ada)
        try:
            expect_denied(c, "insert into public.user_roles (user_id, role_id, granted_by) values (%s, 'visa_officer', %s)", (bob, sam))
        finally:
            reset(c)
    check("Admin cannot record someone else as the granter", admin_cannot_forge_granted_by)

    def audit_trail():
        # super_admin (granted directly by the database owner: actor = null),
        # admin (by Sam) and booking_manager (by Ada).
        n = one(c, "select count(*) from public.admin_audit_logs where action='role.granted'")
        assert n == 3, f"expected 3 role.granted entries, got {n}"
        assert one(c, "select actor_id from public.admin_audit_logs where details->>'role'='super_admin'") is None
        assert one(c, "select actor_id::text from public.admin_audit_logs where details->>'role'='admin'") == sam
        as_user(c, ada)
        try:
            assert one(c, "select count(*) from public.admin_audit_logs") == 3
            c.execute("delete from public.user_roles where user_id=%s and role_id='booking_manager'", (ben,))
            expect_denied(c, "update public.admin_audit_logs set action='role.hidden'")
            expect_denied(c, "delete from public.admin_audit_logs")
        finally:
            reset(c)
        assert one(c, "select count(*) from public.admin_audit_logs where action='role.revoked'") == 1
        c.execute("insert into public.user_roles (user_id, role_id) values (%s, 'booking_manager')", (ben,))
    check("Role changes are audit-logged; admins can read but nobody can edit/delete logs", audit_trail)

    # --- addresses ---------------------------------------------------------------
    addr = {}

    def customer_address_crud():
        as_user(c, alice)
        try:
            addr["a1"] = one(c, "insert into public.addresses (label, region, area, building, is_default) values ('Home','Dubai','Marina','Tower 1', true) returning id")
            addr["a2"] = one(c, "insert into public.addresses (label, region, area, building, is_default) values ('Work','Abu Dhabi','Khalifa City','Office 9', true) returning id")
            assert one(c, "select count(*) from public.addresses where is_default") == 1, "only one default allowed"
            assert one(c, "select is_default from public.addresses where id=%s", (addr["a2"],)) is True
            c.execute("update public.addresses set apartment='1204' where id=%s", (addr["a1"],))
        finally:
            reset(c)
    check("Customer adds/edits addresses; new default replaces old", customer_address_crud)

    def address_validation():
        as_user(c, alice)
        try:
            expect_violation(c, "insert into public.addresses (region, area, building) values ('Doha','X','Y')")
            expect_violation(c, "insert into public.addresses (region, area, building, latitude) values ('Dubai','X','Y', 25.2)")
            c.execute("insert into public.addresses (country_code, region, area, building) values ('QA','Doha','West Bay','Tower')")
        finally:
            reset(c)
    check("Invalid emirate / half coordinates rejected; other GCC countries allowed", address_validation)

    def other_customer_blocked():
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.addresses") == 0
            c.execute("update public.addresses set area='Hacked' where id=%s", (addr["a1"],))
            c.execute("delete from public.addresses where id=%s", (addr["a1"],))
            expect_denied(c, "insert into public.addresses (user_id, region, area, building) values (%s,'Dubai','X','Y')", (alice,))
        finally:
            reset(c)
        assert one(c, "select area from public.addresses where id=%s", (addr["a1"],)) == "Marina"
    check("Another customer cannot see, edit, delete or create someone's addresses", other_customer_blocked)

    def booking_manager_reads():
        as_user(c, ben)
        try:
            assert one(c, "select count(*) from public.addresses") == 3
            c.execute("update public.addresses set area='Changed' where id=%s", (addr["a1"],))
        finally:
            reset(c)
        assert one(c, "select area from public.addresses where id=%s", (addr["a1"],)) == "Marina"
    check("Booking manager can view (not edit) customer addresses", booking_manager_reads)

    # --- app settings ------------------------------------------------------------
    c.execute("insert into public.app_settings (key, value, is_public) values ('internal.secret_flag', 'true', false)")

    def guest_reads_public_settings_only():
        as_user(c, None)
        try:
            assert one(c, "select value::text from public.app_settings where key='auth.sms_fallback_enabled'") == "false"
            assert one(c, "select count(*) from public.app_settings where key='internal.secret_flag'") == 0
            expect_denied(c, "update public.app_settings set value='true' where key='auth.sms_fallback_enabled'")
        finally:
            reset(c)
    check("Guest reads public settings only and cannot change them", guest_reads_public_settings_only)

    def customer_cannot_change_settings():
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.app_settings where key='internal.secret_flag'") == 0
            c.execute("update public.app_settings set value='true' where key='auth.sms_fallback_enabled'")
            expect_denied(c, "insert into public.app_settings (key, value) values ('x.y','1')")
            expect_denied(c, "delete from public.app_settings")
        finally:
            reset(c)
        assert one(c, "select value::text from public.app_settings where key='auth.sms_fallback_enabled'") == "false"
    check("Customer cannot change, add or delete settings", customer_cannot_change_settings)

    def admin_changes_value_audited():
        as_user(c, ada)
        try:
            assert one(c, "select count(*) from public.app_settings where key='internal.secret_flag'") == 1
            c.execute("update public.app_settings set value='true' where key='auth.sms_fallback_enabled'")
            expect_denied(c, "update public.app_settings set is_public=false where key='auth.sms_fallback_enabled'")
            expect_denied(c, "update public.app_settings set updated_by=%s where key='auth.sms_fallback_enabled'", (sam,))
            expect_denied(c, "insert into public.app_settings (key, value) values ('x.y','1')")
            expect_denied(c, "delete from public.app_settings")
        finally:
            reset(c)
        assert one(c, "select value::text from public.app_settings where key='auth.sms_fallback_enabled'") == "true"
        assert one(c, "select updated_by::text from public.app_settings where key='auth.sms_fallback_enabled'") == ada
        assert one(c, "select count(*) from public.admin_audit_logs where action='setting.updated' and entity_id='auth.sms_fallback_enabled' and actor_id=%s", (ada,)) == 1
    check("Admin changes a value only; change is recorded and audit-logged", admin_changes_value_audited)

    # --- catalogue (categories, services, promotions, media) ----------------------
    def guest_reads_live_catalogue():
        as_user(c, None)
        try:
            assert one(c, "select count(*) from public.service_categories") == 11
            assert one(c, "select count(*) from public.services") == 20
            assert one(c, "select count(*) from public.services where is_popular") == 5
            assert one(c, "select count(*) from public.promotions") == 2
            assert one(c, "select count(*) from public.services where base_price is not null") == 0, \
                "no invented prices"
        finally:
            reset(c)
    check("Guest reads the live catalogue (11 categories, 20 services, 2 banners, no prices)", guest_reads_live_catalogue)

    def hidden_content_is_hidden():
        c.execute("update public.service_categories set is_active=false where slug='nurse'")
        c.execute("insert into public.promotions (title, ends_at) values ('Expired offer', now() - interval '1 day')")
        c.execute("insert into public.promotions (title, starts_at) values ('Future offer', now() + interval '1 day')")
        as_user(c, None)
        try:
            assert one(c, "select count(*) from public.service_categories where slug='nurse'") == 0
            assert one(c, "select count(*) from public.services where slug='nurse-at-home'") == 0, \
                "services of a hidden category must be hidden"
            assert one(c, "select count(*) from public.promotions") == 2, "expired/future banners hidden"
        finally:
            reset(c)
        as_user(c, ada)
        try:
            assert one(c, "select count(*) from public.service_categories where slug='nurse'") == 1
            assert one(c, "select count(*) from public.promotions") == 4
        finally:
            reset(c)
        c.execute("update public.service_categories set is_active=true where slug='nurse'")
    check("Hidden categories (and their services) and out-of-date banners are hidden; admins see all", hidden_content_is_hidden)

    def customer_cannot_change_catalogue():
        as_user(c, alice)
        try:
            expect_denied(c, "insert into public.service_categories (slug, name) values ('x','X')")
            expect_denied(c, "insert into public.promotions (title, discount_percent) values ('Fake', 90)")
            c.execute("update public.services set base_price=1, price_unit='fixed'")
            c.execute("delete from public.promotions")
        finally:
            reset(c)
        assert one(c, "select count(*) from public.services where base_price is not null") == 0
        assert one(c, "select count(*) from public.promotions where is_active") >= 2
    check("Customer cannot add, change or delete catalogue content", customer_cannot_change_catalogue)

    def admin_manages_catalogue_audited():
        as_user(c, ada)
        try:
            c.execute("update public.services set base_price=120, price_unit='per_visit' where slug='home-cleaning'")
            c.execute("insert into public.promotions (title, discount_percent) values ('Ramadan offer', 20)")
            expect_violation(c, "update public.services set base_price=50, price_unit=null where slug='deep-cleaning'")
            expect_violation(c, "insert into public.promotions (title, discount_percent) values ('Bad', 150)")
        finally:
            reset(c)
        assert one(c, "select base_price::text from public.services where slug='home-cleaning'") == "120.00"
        assert one(c, "select count(*) from public.admin_audit_logs where action='services.updated' and actor_id=%s", (ada,)) == 1
        assert one(c, "select count(*) from public.admin_audit_logs where action='promotions.created' and actor_id=%s", (ada,)) == 1
    check("Admin sets prices and offers (validated) and every change is audit-logged", admin_manages_catalogue_audited)

    def media_upload_admin_only():
        as_user(c, alice)
        try:
            expect_denied(c, "insert into storage.objects (bucket_id, name) values ('app-media', 'banners/x.jpg')")
        finally:
            reset(c)
        c.execute("insert into storage.buckets (id, name) values ('other', 'other') on conflict do nothing")
        as_user(c, ada)
        try:
            c.execute("insert into storage.objects (bucket_id, name) values ('app-media', 'banners/ok.jpg')")
            expect_denied(c, "insert into storage.objects (bucket_id, name) values ('other', 'x.jpg')")
        finally:
            reset(c)
        assert one(c, "select public::text from storage.buckets where id='app-media'") == "true"
    check("Only admins upload to the public media bucket (and only to that bucket)", media_upload_admin_only)

    # --- recruitment ---------------------------------------------------------------
    rita = new_user(c, "rita@example.com", "Rita Recruiter")
    c.execute("insert into public.user_roles (user_id, role_id) values (%s, 'recruitment_officer')", (rita,))
    kenya = one(c, "select candidate_id::text from public.candidate_private_details where full_name='Wanjiru Kamau'")
    myanmar = one(c, "select candidate_id::text from public.candidate_private_details where full_name='Thandar Aung'")
    monthly = one(c, "select id::text from public.recruitment_packages where slug='live-in-monthly'")
    yearly = one(c, "select id::text from public.recruitment_packages where slug='live-in-yearly'")
    gcc = one(c, "select id::text from public.recruitment_packages where slug='two-year-gcc-sponsor'")

    def test_candidates_seeded():
        assert one(c, "select count(*) from public.candidates where is_test") == 3
        assert one(c, "select code from public.candidates where id=%s", (kenya,)).startswith("GM-")
        expected_age = one(c, "select date_part('year', age(current_date, date '1992-04-12'))::int")
        assert one(c, "select age from public.candidates where id=%s", (kenya,)) == expected_age
        assert one(c, "select display_name from public.candidates where id=%s", (kenya,)) == "Wanjiru Kamau"
    check("TEST candidates seeded with codes, computed ages and allowed names", test_candidates_seeded)

    card = "id, code, display_name, photo_path, nationality, age, designation, accommodation, years_experience, expected_salary, availability_status, available_from, is_featured, is_test, created_at"

    def guest_sees_cards_only():
        as_user(c, None)
        try:
            assert one(c, f"select count(*) from (select {card} from public.candidates) x") == 3
            for column in ["marital_status", "bio", "consent_obtained_at"]:
                expect_denied(c, f"select {column} from public.candidates")
            expect_denied(c, "select * from public.candidate_private_details")
            expect_denied(c, "select * from public.candidate_experience")
            expect_denied(c, "select * from public.candidate_documents")
            assert one(c, "select count(*) from public.candidate_skills where candidate_id=%s", (kenya,)) == 4
            assert one(c, "select count(*) from public.candidate_languages where candidate_id=%s", (kenya,)) == 3
            assert one(c, "select count(*) from public.recruitment_packages") == 3
            expect_denied(c, "insert into public.hiring_requests (package_id, duration_months, customer_name, customer_phone, emirate) values (%s, 3, 'X', '0501234567', 'Dubai')", (monthly,))
        finally:
            reset(c)
    check("Guest sees candidate cards only (no marital status, bio, history, private details or documents)", guest_sees_cards_only)

    def customer_sees_profile_not_private():
        as_user(c, alice)
        try:
            assert one(c, "select religion from public.candidates where id=%s", (kenya,)) == "Christian"
            assert one(c, "select count(*) from public.candidate_experience where candidate_id=%s", (kenya,)) == 2
            assert one(c, "select count(*) from public.candidate_private_details") == 0
            c.execute("update public.candidates set expected_salary=1 where id=%s", (kenya,))
            expect_denied(c, "insert into public.candidates (nationality) values ('Kenya')")
        finally:
            reset(c)
        assert one(c, "select expected_salary::int from public.candidates where id=%s", (kenya,)) == 1800
    check("Customer sees the full profile but never private details, and cannot edit candidates", customer_sees_profile_not_private)

    def hidden_candidates_and_rules():
        c.execute("update public.candidates set archived_at=now() where id=%s", (myanmar,))
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.candidates where id=%s", (myanmar,)) == 0
            assert one(c, "select count(*) from public.candidate_skills where candidate_id=%s", (myanmar,)) == 0
        finally:
            reset(c)
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from public.candidates where id=%s", (myanmar,)) == 1
            assert one(c, "select full_name from public.candidate_private_details where candidate_id=%s", (myanmar,)) == "Thandar Aung"
            expect_violation(c, "insert into public.candidates (nationality, is_published) values ('Kenya', true)")
            new_id = one(c, "insert into public.candidates (nationality) values ('Ethiopia') returning id::text")
            expect_violation(c, "insert into public.candidate_private_details (candidate_id, full_name, date_of_birth) values (%s, 'Too Young', current_date - interval '16 years')", (new_id,))
        finally:
            reset(c)
        c.execute("update public.candidates set archived_at=null where id=%s", (myanmar,))
    check("Archived candidates hidden from customers; staff see all; consent required to publish; under-18 rejected", hidden_candidates_and_rules)

    def documents_protected():
        as_user(c, rita)
        try:
            expect_violation(c, "insert into public.candidate_documents (candidate_id, document_type, title, storage_path, is_customer_visible) values (%s, 'passport', 'Passport', 'k/passport.pdf', true)", (kenya,))
            c.execute("insert into public.candidate_documents (candidate_id, document_type, title, storage_path) values (%s, 'passport', 'Passport', 'k/passport.pdf')", (kenya,))
            c.execute("insert into public.candidate_documents (candidate_id, document_type, title, storage_path, is_customer_visible) values (%s, 'certificate', 'Housekeeping certificate', 'k/cert.pdf', true)", (kenya,))
            c.execute("insert into storage.objects (bucket_id, name) values ('candidate-documents', 'k/passport.pdf'), ('candidate-documents', 'k/cert.pdf')")
        finally:
            reset(c)
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.candidate_documents") == 1
            assert one(c, "select title from public.candidate_documents") == "Housekeeping certificate"
            assert one(c, "select count(*) from storage.objects where bucket_id='candidate-documents'") == 1
            assert one(c, "select name from storage.objects where bucket_id='candidate-documents'") == "k/cert.pdf"
            expect_denied(c, "insert into storage.objects (bucket_id, name) values ('candidate-photos', 'x.jpg')")
        finally:
            reset(c)
        as_user(c, None)
        try:
            assert one(c, "select count(*) from storage.objects where bucket_id='candidate-documents'") == 0
        finally:
            reset(c)
    check("Passports can never be customer-visible; customers open only visible documents; guests none", documents_protected)

    def favourites_private():
        as_user(c, alice)
        try:
            c.execute("insert into public.candidate_favourites (candidate_id) values (%s)", (kenya,))
            assert one(c, "select count(*) from public.candidate_favourites") == 1
        finally:
            reset(c)
        unpublished = one(c, "insert into public.candidates (nationality) values ('Indonesia') returning id::text")
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.candidate_favourites") == 0
            expect_denied(c, "insert into public.candidate_favourites (candidate_id) values (%s)", (unpublished,))
            expect_denied(c, "insert into public.candidate_favourites (user_id, candidate_id) values (%s, %s)", (alice, myanmar))
        finally:
            reset(c)
    check("Favourites are private to each customer and only for live candidates", favourites_private)

    req = {}

    def hiring_request_rules():
        base = "insert into public.hiring_requests (package_id, duration_months, sponsor_nationality, candidate_id, customer_name, customer_phone, emirate) values (%s, %s, %s, %s, 'Alice Customer', '+971501234567', 'Dubai')"
        as_user(c, alice)
        try:
            rid, ref, status = c.execute(base + " returning id::text, reference, status", (monthly, 3, None, kenya)).fetchone()
            req["id"] = rid
            assert ref.startswith("HR-") and len(ref) == len("HR-2026-000001"), ref
            assert status == "submitted"
            expect_violation(c, base, (monthly, 12, None, kenya))
            expect_violation(c, base, (yearly, 18, None, kenya))
            expect_violation(c, base, (gcc, 24, None, kenya))
            c.execute(base, (gcc, 24, 'AE', kenya))
            c.execute(base, (yearly, 24, None, None))
            assert one(c, "select count(*) from public.hiring_requests") == 3
        finally:
            reset(c)
        assert one(c, "select count(*) from public.hiring_request_history where request_id=%s", (req["id"],)) == 1
    check("Hiring requests: reference generated; duration, sponsor nationality and package rules enforced", hiring_request_rules)

    def hiring_request_privacy_and_cancel():
        c.execute("update public.candidates set availability_status='hired' where id=%s", (myanmar,))
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.hiring_requests") == 0
            c.execute("update public.hiring_requests set status='cancelled' where id=%s", (req["id"],))
            expect_violation(c, "insert into public.hiring_requests (package_id, duration_months, candidate_id, customer_name, customer_phone, emirate) values (%s, 2, %s, 'Bob', '0501112222', 'Dubai')", (monthly, myanmar))
        finally:
            reset(c)
        assert one(c, "select status from public.hiring_requests where id=%s", (req["id"],)) == "submitted"
        as_user(c, alice)
        try:
            expect_denied(c, "update public.hiring_requests set status='completed' where id=%s", (req["id"],))
            expect_denied(c, "update public.hiring_requests set assigned_officer_id=%s where id=%s", (alice, req["id"]))
            expect_denied(c, "update public.hiring_requests set customer_name='Changed' where id=%s", (req["id"],))
            c.execute("update public.hiring_requests set status='cancelled' where id=%s", (req["id"],))
            assert one(c, "select count(*) from public.hiring_request_history where request_id=%s", (req["id"],)) == 2
        finally:
            reset(c)
    check("Customers see only their requests, can only cancel unprocessed ones; unavailable workers rejected", hiring_request_privacy_and_cancel)

    def staff_manage_requests():
        other = one(c, "select id::text from public.hiring_requests where status='submitted' and package_id=%s", (gcc,))
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from public.hiring_requests") == 3
            c.execute("update public.hiring_requests set status='shortlisted', assigned_officer_id=%s where id=%s", (rita, other))
            c.execute("insert into public.hiring_request_history (request_id, status, note, is_customer_visible) values (%s, 'shortlisted', 'Internal: check references', false)", (other,))
        finally:
            reset(c)
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.hiring_request_history where request_id=%s", (other,)) == 2, "internal notes hidden"
            expect_denied(c, "update public.hiring_requests set status='cancelled' where id=%s", (other,))
            expect_denied(c, "insert into public.hiring_request_history (request_id, status) values (%s, 'completed')", (other,))
        finally:
            reset(c)
    check("Recruitment staff manage all requests; internal notes hidden; customers cannot cancel after shortlisting", staff_manage_requests)

    def age_refresh_job():
        c.execute("update public.candidates set age=null where id=%s", (kenya,))
        c.execute("select private.refresh_candidate_ages()")
        assert one(c, "select age from public.candidates where id=%s", (kenya,)) is not None
    check("Daily age refresh restores ages", age_refresh_job)

    # --- candidate enquiries ("Request Info") ---------------------------------
    enquiry_sql = (
        "insert into public.candidate_enquiries (candidate_id, customer_name, customer_phone, message, contact_method) "
        "values (%s, 'Alice Customer', '+971501234567', %s, 'whatsapp') returning id::text"
    )

    def enquiry_sent_and_private():
        as_user(c, alice)
        try:
            eid = one(c, enquiry_sql, (kenya, "  Is she available in January?  "))
            row = c.execute("select reference, status, message, customer_id::text from public.candidate_enquiries where id=%s", (eid,)).fetchone()
            assert row[0].startswith("EQ-") and len(row[0]) == 14, row[0]
            assert row[1] == "new" and row[2] == "Is she available in January?", row
            assert row[3] == alice
            # Cannot send in someone else's name, change, or delete it.
            expect_denied(c, "insert into public.candidate_enquiries (customer_id, candidate_id, customer_name, customer_phone, message) values (%s, %s, 'Bob', '+971501111111', 'hi')", (bob, kenya))
            expect_denied(c, "update public.candidate_enquiries set message='changed' where id=%s", (eid,))
            c.execute("update public.candidate_enquiries set status='closed' where id=%s", (eid,))
            expect_denied(c, "delete from public.candidate_enquiries where id=%s", (eid,))
        finally:
            reset(c)
        assert one(c, "select status from public.candidate_enquiries where id=%s", (eid,)) == "new", "customer must not change status"
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.candidate_enquiries") == 0, "other customers see nothing"
        finally:
            reset(c)
        as_user(c, None)
        try:
            expect_denied(c, "select * from public.candidate_enquiries")
            expect_denied(c, enquiry_sql, (kenya, "guest"))
        finally:
            reset(c)
    check("Enquiries: customers send and see only their own, cannot edit or delete; guests none", enquiry_sent_and_private)

    def enquiry_validation_and_rate_limit():
        as_user(c, bob)
        try:
            expect_violation(c, enquiry_sql, (kenya, "   "))
            expect_violation(c, enquiry_sql, (kenya, "x" * 1001))
            for i in range(5):
                one(c, enquiry_sql, (kenya, f"question {i}"))
            expect_violation(c, enquiry_sql, (kenya, "sixth"))
        finally:
            reset(c)
        c.execute("update public.candidates set archived_at=now() where id=%s", (kenya,))
        as_user(c, alice)
        try:
            expect_violation(c, enquiry_sql, (kenya, "archived"))
        finally:
            reset(c)
        c.execute("update public.candidates set archived_at=null where id=%s", (kenya,))
    check("Enquiries: empty/too long rejected, archived candidates rejected, max 5 per hour", enquiry_validation_and_rate_limit)

    def staff_handle_enquiries():
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from public.candidate_enquiries") == 6
            eid = one(c, "select id::text from public.candidate_enquiries where customer_id=%s limit 1", (alice,))
            c.execute("update public.candidate_enquiries set status='in_progress', handled_by=%s where id=%s", (rita, eid))
            assert one(c, "select status from public.candidate_enquiries where id=%s", (eid,)) == "in_progress"
            expect_violation(c, "update public.candidate_enquiries set status='done' where id=%s", (eid,))
            expect_denied(c, "update public.candidate_enquiries set message='edited' where id=%s", (eid,))
        finally:
            reset(c)
        as_user(c, ben)
        try:
            assert one(c, "select count(*) from public.candidate_enquiries") == 0, "booking manager is not recruitment staff"
        finally:
            reset(c)
    check("Recruitment staff read all enquiries and update status only; other staff see none", staff_handle_enquiries)

    # --- staff status updates with notes (update_hiring_status) ---------------
    def status_update_with_note():
        as_user(c, alice)
        try:
            rid = one(c, "insert into public.hiring_requests (package_id, duration_months, candidate_id, customer_name, customer_phone, emirate) values (%s, 2, %s, 'Alice Customer', '+971501234567', 'Dubai') returning id::text", (monthly, kenya))
        finally:
            reset(c)
        as_user(c, rita)
        try:
            c.execute("select public.update_hiring_status(%s, 'under_review', '  We are reviewing your request.  ', true)", (rid,))
            rows = c.execute("select status, note, is_customer_visible, created_by::text from public.hiring_request_history where request_id=%s order by id", (rid,)).fetchall()
            assert [r[0] for r in rows] == ["submitted", "under_review"], rows
            assert rows[1][1] == "We are reviewing your request." and rows[1][2] is True and rows[1][3] == rita, rows[1]
            # Internal note without a status change.
            c.execute("select public.update_hiring_status(%s, 'under_review', 'Customer prefers Kenyan maids.', false)", (rid,))
            # Status change without a note; empty note-only call does nothing.
            c.execute("select public.update_hiring_status(%s, 'shortlisted')", (rid,))
            c.execute("select public.update_hiring_status(%s, 'shortlisted', '   ', true)", (rid,))
            rows = c.execute("select status, note, is_customer_visible from public.hiring_request_history where request_id=%s order by id", (rid,)).fetchall()
            assert rows == [("submitted", "", True), ("under_review", "We are reviewing your request.", True),
                            ("under_review", "Customer prefers Kenyan maids.", False), ("shortlisted", "", True)], rows
            expect_violation(c, "select public.update_hiring_status(%s, 'done')", (rid,))
            expect_violation(c, "select public.update_hiring_status(%s, 'rejected', %s)", (rid, "x" * 2001))
        finally:
            reset(c)
        as_user(c, alice)
        try:
            notes = [r[0] for r in c.execute("select note from public.hiring_request_history where request_id=%s order by id", (rid,)).fetchall()]
            assert "Customer prefers Kenyan maids." not in notes, "internal note leaked to customer"
            assert len(notes) == 3, notes
            expect_denied(c, "select public.update_hiring_status(%s, 'completed', 'hack', true)", (rid,))
            # The customer's own cancel still records a plain entry.
        finally:
            reset(c)
        as_user(c, None)
        try:
            expect_denied(c, "select public.update_hiring_status(%s, 'completed')", (rid,))
        finally:
            reset(c)
        assert one(c, "select status from public.hiring_requests where id=%s", (rid,)) == "shortlisted"
    check("Staff status updates: note on the same timeline entry, internal notes hidden, customers and guests refused", status_update_with_note)

    # --- save_candidate (staff website) ----------------------------------------
    save_sql = "select public.save_candidate(%s::jsonb, %s::jsonb, %s::text[], %s::jsonb, %s::jsonb, %s::uuid[])::text"

    def candidate_json(**over):
        base = {"id": None, "nationality": "Ethiopia", "designation": "Nanny", "accommodation": "live_in",
                "years_experience": 3, "religion": "Christian", "marital_status": "Single",
                "expected_salary": 1700, "availability_status": "available", "bio": "Kind and patient.",
                "show_full_name": True, "is_published": True, "is_featured": False,
                "consent_obtained_at": "2026-11-16T10:00:00Z", "archived": False}
        base.update(over)
        return psycopg.types.json.Jsonb(base)

    private_json = psycopg.types.json.Jsonb({"full_name": "Abeba Tadesse", "date_of_birth": "1996-05-10",
                                              "passport_number": "EP1234567", "internal_notes": "Referred by agent."})
    langs = psycopg.types.json.Jsonb([{"language": "Amharic", "proficiency": "fluent"}, {"language": "English", "proficiency": "good"}])
    jobs = psycopg.types.json.Jsonb([{"country": "Lebanon", "role": "Nanny", "start_year": 2020, "end_year": 2023, "description": ""}])

    def save_candidate_rules():
        as_user(c, rita)
        try:
            cid = one(c, save_sql, (candidate_json(), private_json, ["childcare", "cooking"], langs, jobs, [monthly, yearly]))
            row = c.execute("select display_name, age, is_published, code from public.candidates where id=%s", (cid,)).fetchone()
            assert row[0] == "Abeba Tadesse" and row[1] is not None and row[2] is True and row[3].startswith("GM-"), row
            assert one(c, "select count(*) from public.candidate_skills where candidate_id=%s", (cid,)) == 2
            assert one(c, "select count(*) from public.candidate_languages where candidate_id=%s", (cid,)) == 2
            assert one(c, "select count(*) from public.candidate_experience where candidate_id=%s", (cid,)) == 1
            assert one(c, "select count(*) from public.candidate_packages where candidate_id=%s", (cid,)) == 2
            # Update: lists replaced, name hidden, archived.
            same = one(c, save_sql, (candidate_json(id=cid, show_full_name=False, archived=True), private_json,
                                     ["cleaning"], psycopg.types.json.Jsonb([]), psycopg.types.json.Jsonb([]), [monthly]))
            assert same == cid
            row = c.execute("select display_name, archived_at is not null from public.candidates where id=%s", (cid,)).fetchone()
            assert row == (None, True), row
            assert one(c, "select count(*) from public.candidate_skills where candidate_id=%s", (cid,)) == 1
            assert one(c, "select count(*) from public.candidate_languages where candidate_id=%s", (cid,)) == 0
            # All-or-nothing: an invalid skill leaves the candidate unchanged.
            expect_violation(c, save_sql, (candidate_json(id=cid, bio="Changed"), private_json, ["flying"],
                                           langs, jobs, [monthly]))
            assert one(c, "select bio from public.candidates where id=%s", (cid,)) == "Kind and patient."
            assert one(c, "select count(*) from public.candidate_skills where candidate_id=%s", (cid,)) == 1
            # Publishing needs consent; name and date of birth are required.
            expect_violation(c, save_sql, (candidate_json(consent_obtained_at=None), private_json, [], langs, jobs, []))
            expect_violation(c, save_sql, (candidate_json(), psycopg.types.json.Jsonb({"full_name": " ", "date_of_birth": None}), [], langs, jobs, []))
            # Under 18 is rejected.
            expect_violation(c, save_sql, (candidate_json(), psycopg.types.json.Jsonb({"full_name": "Too Young", "date_of_birth": "2015-01-01"}), [], langs, jobs, []))
        finally:
            reset(c)
        assert one(c, "select count(*) from public.admin_audit_logs where entity_type='candidates' and entity_id=%s", (cid,)) >= 2, "changes are audit-logged"
        as_user(c, alice)
        try:
            expect_denied(c, save_sql, (candidate_json(), private_json, [], langs, jobs, []))
            expect_denied(c, save_sql, (candidate_json(id=cid), private_json, [], langs, jobs, []))
        finally:
            reset(c)
        as_user(c, None)
        try:
            expect_denied(c, save_sql, (candidate_json(), private_json, [], langs, jobs, []))
        finally:
            reset(c)
    check("save_candidate: all-or-nothing save with private details and lists; consent/age rules; customers and guests refused", save_candidate_rules)

    def photo_records_for_staff():
        c.execute("insert into storage.objects (bucket_id, name) values ('candidate-photos', 'k/photo-1.jpg')")
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from storage.objects where bucket_id='candidate-photos' and name='k/photo-1.jpg'") == 1
            c.execute("delete from storage.objects where bucket_id='candidate-photos' and name='k/photo-1.jpg'")
        finally:
            reset(c)
        assert one(c, "select count(*) from storage.objects where name='k/photo-1.jpg'") == 0, "staff could not remove the photo"
        c.execute("insert into storage.objects (bucket_id, name) values ('candidate-photos', 'k/photo-2.jpg')")
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from storage.objects where bucket_id='candidate-photos'") == 0
            c.execute("delete from storage.objects where name='k/photo-2.jpg'")
        finally:
            reset(c)
        assert one(c, "select count(*) from storage.objects where name='k/photo-2.jpg'") == 1, "customer removed a photo"
    check("Staff can see and remove candidate photo files; customers cannot", photo_records_for_staff)

    # --- bookings (Phase 3) ------------------------------------------------------
    from datetime import datetime, timedelta
    from zoneinfo import ZoneInfo

    dubai = ZoneInfo("Asia/Dubai")
    day = (datetime.now(dubai) + timedelta(days=3)).date()

    def at(hour, minute=0, days=0):
        d = day + timedelta(days=days)
        return datetime(d.year, d.month, d.day, hour, minute, tzinfo=dubai)

    svc = {slug: one(c, "select id::text from public.services where slug=%s", (slug,))
           for slug in ["home-cleaning", "babysitting", "deep-cleaning", "nurse-at-home", "pet-care"]}
    c.execute("update public.services set base_price=45, price_unit='per_hour' where slug='home-cleaning'")
    c.execute("update public.services set base_price=350, price_unit='per_visit' where slug='deep-cleaning'")
    cleaner = one(c, "insert into public.service_staff (display_name, years_experience) values ('Grace K.', 5) returning id::text")
    nanny = one(c, "insert into public.service_staff (display_name) values ('Mary N.') returning id::text")
    c.execute("insert into public.service_staff_private (staff_id, full_name, phone) values (%s, 'Grace Kamau', '+971500000001')", (cleaner,))
    c.execute("insert into public.service_staff_categories (staff_id, category_id) select %s, id from public.service_categories where slug in ('general-cleaning', 'deep-cleaning')", (cleaner,))
    c.execute("insert into public.service_staff_categories (staff_id, category_id) select %s, id from public.service_categories where slug='nanny-baby-care'", (nanny,))

    book_sql = ("insert into public.bookings (service_id, hours, starts_at, emirate, area, building, customer_name, customer_phone) "
                "values (%s, %s, %s, 'Dubai', 'JLT', 'Cluster X, Tower 1', 'Alice Customer', '+971501234567') returning id::text")
    bk = {}

    def booking_rules():
        as_user(c, alice)
        try:
            bk["a10"] = one(c, book_sql, (svc["home-cleaning"], 3, at(10)))
            row = c.execute("select reference, status, booking_type, service_name, price_estimate, ends_at from public.bookings where id=%s", (bk["a10"],)).fetchone()
            assert row[0].startswith("BK-") and len(row[0]) == 14 and row[1] == "pending" and row[2] == "hourly", row
            assert row[3] == "Home Cleaning" and float(row[4]) == 135.0 and row[5] == at(13), row
            # Rules: hours 2-8, aligned slots, inside 8 am - 8 pm, notice and window.
            for hours, start in [(1, at(14)), (9, at(8)), (2, at(14, 30)), (2, at(19)), (2, at(7)),
                                 (2, datetime.now(dubai) + timedelta(hours=1)), (2, at(10, days=40))]:
                expect_violation(c, book_sql, (svc["home-cleaning"], hours, start))
            # Visits last 4 h by default; requests need no free staff.
            v = one(c, book_sql, (svc["deep-cleaning"], None, at(14)))
            assert one(c, "select ends_at from public.bookings where id=%s", (v,)) == at(18)
            assert one(c, "select price_estimate from public.bookings where id=%s", (v,)) == 350
            one(c, book_sql, (svc["nurse-at-home"], 5, at(9)))
            # No staff at all for pet care.
            expect_violation(c, book_sql, (svc["pet-care"], 2, at(9)))
            # Customers cannot set prices, references or staff.
            expect_denied(c, "insert into public.bookings (service_id, hours, starts_at, emirate, area, building, customer_name, customer_phone, price_estimate) values (%s, 2, %s, 'Dubai', 'JLT', 'B', 'Alice', '+971501234567', 1)", (svc["home-cleaning"], at(8, days=1)))
        finally:
            reset(c)
        as_user(c, bob)
        try:
            # Only one cleaner (she also does deep cleaning 14-18): overlapping slots are taken.
            expect_violation(c, book_sql, (svc["home-cleaning"], 2, at(11)))
            expect_violation(c, book_sql, (svc["home-cleaning"], 2, at(17)))
            # The nanny is free.
            bk["b11"] = one(c, book_sql, (svc["babysitting"], 2, at(11)))
            # Back-to-back is fine (10-13 then 13-14... 2 h ends 15 overlaps visit at 14) -> 18:00 works.
            bk["b18"] = one(c, book_sql, (svc["home-cleaning"], 2, at(18)))
            assert one(c, "select count(*) from public.bookings") == 2, "customers see only their own bookings"
        finally:
            reset(c)
    check("Bookings: reference and price; hours, slot, working-hours, notice and window rules; capacity per staff category", booking_rules)

    def slots_for_guests():
        as_user(c, None)
        try:
            rows = c.execute("select starts_at, is_available from public.available_slots(%s, %s, 2)", (svc["home-cleaning"], day)).fetchall()
            free = {r[0].astimezone(dubai).hour: r[1] for r in rows}
            assert min(free) == 8 and max(free) == 18, free  # last 2 h slot starts 6 pm
            assert free[8] is True and free[10] is False and free[12] is False and free[15] is False and free[17] is False and free[18] is False, free
            expect_denied(c, "select * from public.bookings")
        finally:
            reset(c)
    check("Available slots: guests see free/taken times only, never bookings", slots_for_guests)

    def staff_assignment():
        as_user(c, ben)
        try:
            c.execute("update public.bookings set assigned_staff_id=%s where id=%s", (cleaner, bk["a10"]))
            c.execute("select public.update_booking_status(%s, 'provider_assigned', 'Grace will arrive at 10 am.', true)", (bk["a10"],))
            c.execute("select public.update_booking_status(%s, 'provider_assigned', 'Gate code 1234.', false)", (bk["a10"],))
            try:
                with c.transaction():
                    c.execute("update public.bookings set assigned_staff_id=%s where id=%s", (cleaner, bk["b11"]))
                raise AssertionError("staff double-booked")
            except errors.ExclusionViolation:
                pass
        finally:
            reset(c)
        as_user(c, alice)
        try:
            assert one(c, "select display_name from public.service_staff") == "Grace K."
            assert one(c, "select count(*) from public.service_staff_private") == 0
            notes = [r[0] for r in c.execute("select note from public.booking_history where booking_id=%s order by id", (bk["a10"],)).fetchall()]
            assert notes == ["", "Grace will arrive at 10 am."], notes
            expect_violation(c, "update public.bookings set status='completed' where id=%s", (bk["a10"],))
            expect_violation(c, "update public.bookings set assigned_staff_id=null where id=%s", (bk["a10"],))
            expect_denied(c, "select public.update_booking_status(%s, 'completed')", (bk["a10"],))
        finally:
            reset(c)
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.service_staff") == 0
        finally:
            reset(c)
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from public.bookings") == 0, "recruitment staff do not manage bookings"
        finally:
            reset(c)
    check("Booking staff assign staff and add notes; no staff double-booking; customers see only their assigned staff and visible notes", staff_assignment)

    def cancel_and_reschedule():
        as_user(c, alice)
        try:
            # Reschedule 10-13 -> next day 10-13: back to pending, staff released.
            c.execute("update public.bookings set starts_at=%s where id=%s", (at(10, days=1), bk["a10"]))
            row = c.execute("select status, assigned_staff_id, ends_at from public.bookings where id=%s", (bk["a10"],)).fetchone()
            assert row == ("pending", None, at(13, days=1)), row
            last = one(c, "select note from public.booking_history where booking_id=%s order by id desc limit 1", (bk["a10"],))
            assert last.startswith("Rescheduled to"), last
            # Moving onto a taken slot is refused.
            expect_violation(c, "update public.bookings set starts_at=%s where id=%s", (at(14), bk["a10"]))
            c.execute("update public.bookings set status='cancelled', cancel_reason='Plans changed' where id=%s", (bk["a10"],))
            assert one(c, "select note from public.booking_history where booking_id=%s order by id desc limit 1", (bk["a10"],)) == "Plans changed"
            expect_violation(c, "update public.bookings set status='pending' where id=%s", (bk["a10"],))
        finally:
            reset(c)
        # Within the cancellation limit, customers must call.
        c.execute("update public.booking_settings set cancel_hours=168")
        as_user(c, bob)
        try:
            expect_violation(c, "update public.bookings set status='cancelled' where id=%s", (bk["b18"],))
        finally:
            reset(c)
        c.execute("update public.booking_settings set cancel_hours=24")
        as_user(c, ben)
        try:
            c.execute("select public.update_booking_status(%s, 'cancelled', 'Customer called to cancel.', true)", (bk["b18"],))
        finally:
            reset(c)
        assert one(c, "select status from public.bookings where id=%s", (bk["b18"],)) == "cancelled"
    check("Customers reschedule (re-checked) and cancel until 24 h before; later only staff can", cancel_and_reschedule)

    def booking_settings_rules():
        as_user(c, None)
        try:
            assert one(c, "select cancel_hours from public.booking_settings") == 24
        finally:
            reset(c)
        as_user(c, alice)
        try:
            c.execute("update public.booking_settings set min_hours=1")
        finally:
            reset(c)
        assert one(c, "select min_hours from public.booking_settings") == 2, "customer changed settings"
        as_user(c, ada)
        try:
            c.execute("update public.booking_settings set close_time='21:00'")
        finally:
            reset(c)
        assert str(one(c, "select close_time from public.booking_settings")) == "21:00:00"
        c.execute("update public.booking_settings set close_time='20:00'")
    check("Booking settings: everyone reads; only administrators change", booking_settings_rules)

    # --- profile essentials (Phase 4.1) -------------------------------------------
    def delete_address_used_by_locked_booking():
        # Alice's cancelled booking a10 used a saved address.
        as_user(c, alice)
        try:
            addr = one(c, "insert into public.addresses (region, area, building) values ('Dubai', 'JLT', 'Tower 9') returning id::text")
        finally:
            reset(c)
        c.execute("set session_replication_role = replica")
        c.execute("update public.bookings set address_id=%s where id=%s", (addr, bk["a10"]))
        c.execute("set session_replication_role = origin")
        assert one(c, "select status from public.bookings where id=%s", (bk["a10"],)) == "cancelled"
        as_user(c, alice)
        try:
            c.execute("delete from public.addresses where id=%s", (addr,))
            assert one(c, "select count(*) from public.addresses where id=%s", (addr,)) == 0
            row = c.execute("select address_id, status, building from public.bookings where id=%s", (bk["a10"],)).fetchone()
            assert row == (None, "cancelled", "Cluster X, Tower 1"), row
            # Customers still cannot change a locked booking otherwise.
            expect_violation(c, "update public.bookings set starts_at=starts_at + interval '1 hour' where id=%s", (bk["a10"],))
        finally:
            reset(c)
    check("Deleting a saved address unlinks it from locked bookings (snapshot kept)", delete_address_used_by_locked_booking)

    def account_deletion_requests():
        as_user(c, None)
        try:
            expect_denied(c, "select * from public.account_deletion_requests")
            expect_denied(c, "insert into public.account_deletion_requests (reason) values ('x')")
        finally:
            reset(c)
        as_user(c, alice)
        try:
            req = one(c, "insert into public.account_deletion_requests (reason) values ('No longer needed') returning id::text")
            row = c.execute("select user_id::text, status from public.account_deletion_requests where id=%s", (req,)).fetchone()
            assert row == (alice, "pending"), row
            # One pending request at a time.
            try:
                with c.transaction():
                    c.execute("insert into public.account_deletion_requests (reason) values ('again')")
                raise AssertionError("second pending request was accepted")
            except errors.UniqueViolation:
                pass
            # Customers cannot set other fields or another user.
            expect_denied(c, "insert into public.account_deletion_requests (user_id, reason) values (%s, 'x')", (bob,))
            expect_denied(c, "insert into public.account_deletion_requests (status) values ('completed')")
            expect_violation(c, "update public.account_deletion_requests set status='completed' where id=%s", (req,))
            expect_violation(c, "update public.account_deletion_requests set staff_note='done' where id=%s", (req,))
            expect_denied(c, "update public.account_deletion_requests set reason='changed' where id=%s", (req,))
            expect_denied(c, "delete from public.account_deletion_requests where id=%s", (req,))
        finally:
            reset(c)
        for other in (bob, ben):
            as_user(c, other)
            try:
                assert one(c, "select count(*) from public.account_deletion_requests") == 0, "others see the request"
                c.execute("update public.account_deletion_requests set status='withdrawn' where id=%s", (req,))
            finally:
                reset(c)
        assert one(c, "select status from public.account_deletion_requests where id=%s", (req,)) == "pending"
        # Alice withdraws, then asks again.
        as_user(c, alice)
        try:
            c.execute("update public.account_deletion_requests set status='withdrawn' where id=%s", (req,))
            assert one(c, "select status from public.account_deletion_requests where id=%s", (req,)) == "withdrawn"
            # A withdrawn request cannot be reopened.
            c.execute("update public.account_deletion_requests set status='pending' where id=%s", (req,))
            assert one(c, "select status from public.account_deletion_requests where id=%s", (req,)) == "withdrawn"
            req2 = one(c, "insert into public.account_deletion_requests (reason) values ('') returning id::text")
        finally:
            reset(c)
        # Administrators see all requests and mark them done.
        as_user(c, sam)
        try:
            assert one(c, "select count(*) from public.account_deletion_requests") == 2
            c.execute("update public.account_deletion_requests set status='completed', staff_note='Login and personal data deleted.' where id=%s", (req2,))
            row = c.execute("select status, handled_by::text, handled_at is not null from public.account_deletion_requests where id=%s", (req2,)).fetchone()
            assert row == ("completed", sam, True), row
            expect_denied(c, "delete from public.account_deletion_requests where id=%s", (req2,))
        finally:
            reset(c)
    check("Account deletion requests: customers request and withdraw their own; only administrators see all and process", account_deletion_requests)

    # --- account deletion processing (A.6) ----------------------------------------
    def account_deletion_processing():
        dina = new_user(c, "dina@example.com", "Dina Leaving")
        as_user(c, dina)
        try:
            addr = one(c, "insert into public.addresses (region, area, building) values ('Dubai', 'JLT', 'Tower 4') returning id::text")
            booking = one(c, "insert into public.bookings (service_id, starts_at, address_id, emirate, area, building, apartment, address_notes, instructions, customer_name, customer_phone) "
                             "values (%s, %s, %s, 'Dubai', 'JLT', 'Tower 4', '801', 'Gate 2', 'Call on arrival', 'Dina Leaving', '+971509998888') returning id::text",
                          (svc["nurse-at-home"], at(10, days=5), addr))
            hiring = one(c, "insert into public.hiring_requests (package_id, duration_months, customer_name, customer_phone, customer_email, emirate, requirements) "
                            "values (%s, 3, 'Dina Leaving', '+971509998888', 'dina@example.com', 'Dubai', 'Two children') returning id::text", (monthly,))
            c.execute("insert into public.candidate_favourites (candidate_id) values (%s)", (kenya,))
            req = one(c, "insert into public.account_deletion_requests (reason) values ('Moving') returning id::text")
            # Customers cannot process requests.
            expect_denied(c, "select public.process_account_deletion(%s)", (req,))
        finally:
            reset(c)
        for staff in (ben, rita):
            as_user(c, staff)
            try:
                expect_denied(c, "select public.process_account_deletion(%s)", (req,))
            finally:
                reset(c)

        def refused(message):
            as_user(c, sam)
            try:
                try:
                    with c.transaction():
                        c.execute("select public.process_account_deletion(%s)", (req,))
                    raise AssertionError("deletion was not refused: " + message)
                except errors.CheckViolation as e:
                    assert message in str(e), str(e)
            finally:
                reset(c)

        refused("upcoming or active bookings")
        c.execute("set session_replication_role = replica")
        c.execute("update public.bookings set status='completed' where id=%s", (booking,))
        c.execute("set session_replication_role = origin")
        refused("open hiring requests")
        c.execute("set session_replication_role = replica")
        c.execute("update public.hiring_requests set status='completed' where id=%s", (hiring,))
        c.execute("set session_replication_role = origin")
        c.execute("insert into public.user_roles (user_id, role_id) values (%s, 'booking_manager')", (dina,))
        refused("staff roles")
        c.execute("delete from public.user_roles where user_id=%s and role_id='booking_manager'", (dina,))

        as_user(c, sam)
        try:
            c.execute("select public.process_account_deletion(%s, 'Done on request.')", (req,))
        finally:
            reset(c)

        assert one(c, "select count(*) from auth.users where id=%s", (dina,)) == 0, "sign-in not removed"
        assert one(c, "select count(*) from public.profiles where id=%s", (dina,)) == 0
        assert one(c, "select count(*) from public.addresses where id=%s", (addr,)) == 0
        assert one(c, "select count(*) from public.candidate_favourites where user_id=%s", (dina,)) == 0
        b = c.execute("select customer_id, customer_name, customer_phone, building, apartment, address_notes, instructions, address_id, area, status from public.bookings where id=%s", (booking,)).fetchone()
        assert b == (None, "Deleted customer", "Removed", "Removed", "", "", "", None, "JLT", "completed"), b
        h = c.execute("select customer_id, customer_name, customer_phone, customer_email, requirements, status from public.hiring_requests where id=%s", (hiring,)).fetchone()
        assert h == (None, "Deleted customer", "Removed", None, "", "completed"), h
        r = c.execute("select user_id, status, staff_note, handled_by::text, handled_at is not null from public.account_deletion_requests where id=%s", (req,)).fetchone()
        assert r == (None, "completed", "Done on request.", sam, True), r
        log = c.execute("select actor_id::text, entity_id, details->>'bookings_kept', details->>'hiring_requests_kept' from public.admin_audit_logs where action='account.deleted'").fetchone()
        assert log == (sam, dina, "1", "1"), log
        refused("no longer pending")
        # Customers still cannot create records without themselves.
        as_user(c, alice)
        try:
            expect_denied(c, "insert into public.bookings (customer_id, service_id, starts_at, emirate, area, building, customer_name, customer_phone) values (null, %s, %s, 'Dubai', 'JLT', 'T', 'Alice', '+971501234567')",
                          (svc["nurse-at-home"], at(11, days=6)))
        finally:
            reset(c)
    check("Account deletion: only admins process; refused with open work or staff roles; sign-in and personal data removed, records kept anonymised and audit-logged", account_deletion_processing)

    def admins_manage_app_media():
        c.execute("insert into storage.objects (bucket_id, name) values ('app-media', 'services/test.jpg')")
        as_user(c, sam)
        try:
            assert one(c, "select count(*) from storage.objects where bucket_id='app-media' and name='services/test.jpg'") == 1
            c.execute("delete from storage.objects where bucket_id='app-media' and name='services/test.jpg'")
        finally:
            reset(c)
        assert one(c, "select count(*) from storage.objects where name='services/test.jpg'") == 0, "admin could not remove the file"
        c.execute("insert into storage.objects (bucket_id, name) values ('app-media', 'services/test2.jpg')")
        for user in (alice, ben):
            as_user(c, user)
            try:
                assert one(c, "select count(*) from storage.objects where bucket_id='app-media'") == 0
                c.execute("delete from storage.objects where bucket_id='app-media'")
            finally:
                reset(c)
        assert one(c, "select count(*) from storage.objects where name='services/test2.jpg'") == 1, "non-admin removed a file"
    check("App images: only admins list, replace and remove them", admins_manage_app_media)

    # --- staff notifications (bell) -------------------------------------------------
    def staff_notifications():
        kinds = dict(c.execute("select kind, count(*) from public.staff_notifications group by kind").fetchall())
        for kind in ["booking.created", "booking.cancelled", "booking.rescheduled", "hiring.created",
                     "enquiry.created", "account.deletion_requested", "account.deletion_withdrawn",
                     "account.signed_up"]:
            assert kinds.get(kind, 0) >= 1, f"no {kind} notification: {kinds}"
        # Staff actions are not notified (staff cancelled b18 by phone).
        assert one(c, "select count(*) from public.staff_notifications where kind='booking.cancelled' and link like %s",
                   ("%" + bk["b18"],)) == 0, "staff cancellation notified"
        # A customer's own reschedule of a10 was notified, with its link.
        assert one(c, "select count(*) from public.staff_notifications where kind='booking.rescheduled' and link=%s",
                   ("/bookings/view/?id=" + bk["a10"],)) == 1
        by_area = dict(c.execute("select area, count(*) from public.staff_notifications group by area").fetchall())

        as_user(c, None)
        try:
            expect_denied(c, "select * from public.staff_notifications")
        finally:
            reset(c)
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.staff_notifications") == 0, "customer sees notifications"
            expect_denied(c, "insert into public.staff_notifications (area, kind, title) values ('admin', 'x.y', 'Fake')")
        finally:
            reset(c)
        for user, areas in ((ben, ["bookings"]), (rita, ["recruitment"]), (sam, ["bookings", "recruitment", "admin"])):
            as_user(c, user)
            try:
                seen = dict(c.execute("select area, count(*) from public.staff_notifications group by area").fetchall())
                assert seen == {a: by_area[a] for a in areas}, (user, seen)
            finally:
                reset(c)

        # Read status is personal.
        recruitment_id = one(c, "select id from public.staff_notifications where area='recruitment' limit 1")
        as_user(c, ben)
        try:
            c.execute("select public.mark_staff_notifications_read()")
            unread = one(c, "select count(*) from public.staff_notifications n where not exists (select 1 from public.staff_notification_reads r where r.notification_id = n.id)")
            assert unread == 0, unread
            assert one(c, "select count(*) from public.staff_notification_reads") == by_area["bookings"]
            expect_denied(c, "insert into public.staff_notification_reads (notification_id) values (%s)", (recruitment_id,))
            # Marking twice is harmless.
            c.execute("select public.mark_staff_notifications_read()")
        finally:
            reset(c)
        as_user(c, sam)
        try:
            assert one(c, "select count(*) from public.staff_notification_reads") == 0, "sam sees ben's reads"
            first = one(c, "select id from public.staff_notifications order by id limit 1")
            c.execute("select public.mark_staff_notifications_read(%s)", ([first],))
            assert one(c, "select count(*) from public.staff_notification_reads") == 1
        finally:
            reset(c)
    check("Staff notifications: app events notify the right area only; staff actions are not notified; read status is per person", staff_notifications)

    # --- maid nationalities and prices per nationality ---------------------------
    def nationalities_and_prices():
        as_user(c, None)
        try:
            names = [r[0] for r in c.execute("select name from public.maid_nationalities order by sort_order").fetchall()]
            assert names == ["Kenya", "Ethiopia", "Myanmar", "Indonesia", "Philippines", "Madagascar"], names
            assert one(c, "select code from public.maid_nationalities where name='Madagascar'") == "MG"
            expect_denied(c, "insert into public.maid_nationalities (name, code) values ('Uganda', 'UG')")
        finally:
            reset(c)
        as_user(c, alice)
        try:
            expect_violation(c, "insert into public.maid_nationalities (name, code) values ('Uganda', 'UG')")
            expect_violation(c, "insert into public.recruitment_package_prices (package_id, nationality, price) values (%s, 'Kenya', 1)", (gcc,))
        finally:
            reset(c)
        as_user(c, sam)
        try:
            c.execute("insert into public.maid_nationalities (name, code, sort_order, is_active) values ('Uganda', 'UG', 70, false)")
            try:
                with c.transaction():
                    c.execute("insert into public.maid_nationalities (name, code) values ('Nowhere', 'nw')")
                raise AssertionError("lower-case code accepted")
            except errors.CheckViolation:
                pass
            c.execute("insert into public.recruitment_package_prices (package_id, nationality, price) values (%s, 'Kenya', 15000), (%s, 'Myanmar', 13500)", (gcc, gcc))
            # A nationality in use cannot be deleted.
            try:
                with c.transaction():
                    c.execute("delete from public.maid_nationalities where name='Kenya'")
                raise AssertionError("deleted a nationality in use")
            except errors.ForeignKeyViolation:
                pass
            # Renaming follows through to candidates and prices.
            c.execute("update public.maid_nationalities set name='Republic of Kenya' where name='Kenya'")
            assert one(c, "select nationality from public.candidates where id=%s", (kenya,)) == "Republic of Kenya"
            assert one(c, "select count(*) from public.recruitment_package_prices where nationality='Republic of Kenya'") == 1
            c.execute("update public.maid_nationalities set name='Kenya' where name='Republic of Kenya'")
        finally:
            reset(c)
        # Hidden nationalities: hidden from guests and customers, visible to recruitment staff.
        for user, expected in ((None, 6), (alice, 6), (rita, 7)):
            as_user(c, user)
            try:
                assert one(c, "select count(*) from public.maid_nationalities") == expected, (user, expected)
            finally:
                reset(c)
        # Candidates must use a listed nationality.
        try:
            with c.transaction():
                c.execute("update public.candidates set nationality='Atlantis' where id=%s", (kenya,))
            raise AssertionError("unknown nationality accepted")
        except errors.ForeignKeyViolation:
            pass

        gcc_sql = ("insert into public.hiring_requests (package_id, duration_months, sponsor_nationality, candidate_id, preferred_nationality, customer_name, customer_phone, emirate) "
                   "values (%s, 24, 'AE', %s, %s, 'Alice Customer', '+971501234567', 'Dubai') returning id::text")
        as_user(c, alice)
        try:
            # Agency recommends: a nationality must be chosen, and an active one.
            expect_violation(c, gcc_sql, (gcc, None, None))
            expect_violation(c, gcc_sql, (gcc, None, "Uganda"))
            r1 = one(c, gcc_sql, (gcc, None, "Myanmar"))
            # A chosen maid decides the nationality, whatever was sent.
            r2 = one(c, gcc_sql, (gcc, kenya, "Myanmar"))
            # No price set for the nationality: on request.
            r3 = one(c, gcc_sql, (gcc, None, "Ethiopia"))
            # The customer cannot set the quoted price.
            expect_denied(c, "insert into public.hiring_requests (package_id, duration_months, sponsor_nationality, preferred_nationality, customer_name, customer_phone, emirate, quoted_price) values (%s, 24, 'AE', 'Kenya', 'Alice', '+971501234567', 'Dubai', 1)", (gcc,))
            m = one(c, "insert into public.hiring_requests (package_id, duration_months, customer_name, customer_phone, emirate) values (%s, 3, 'Alice Customer', '+971501234567', 'Dubai') returning id::text", (monthly,))
        finally:
            reset(c)
        q = lambda rid: c.execute("select preferred_nationality, quoted_price, quoted_price_unit from public.hiring_requests where id=%s", (rid,)).fetchone()
        assert q(r1) == ("Myanmar", 13500, "total"), q(r1)
        assert q(r2) == ("Kenya", 15000, "total"), q(r2)
        assert q(r3) == ("Ethiopia", None, None), q(r3)
        monthly_price = c.execute("select price, price_unit from public.recruitment_packages where id=%s", (monthly,)).fetchone()
        mq = q(m)
        assert mq[0] is None and mq[1] == monthly_price[0] and (mq[2] == (monthly_price[1] if monthly_price[0] is not None else None)), (mq, monthly_price)
    check("Nationalities: admins manage the list (codes, rename, hide, no delete in use); 2-Year prices per nationality; hiring requests keep nationality and quoted price", nationalities_and_prices)

    # --- customer notifications -------------------------------------------------
    def customer_notifications():
        def rows(uid):
            return c.execute(
                "select kind, title, body, booking_id::text, hiring_request_id::text, candidate_id::text, read_at "
                "from public.customer_notifications where customer_id=%s order by id", (uid,)).fetchall()

        alice_rows = rows(alice)
        kinds = [r[0] for r in alice_rows]
        # Staff actions on Alice's booking a10, hiring requests and enquiry earlier in these tests.
        assigned = [r for r in alice_rows if r[0] == "booking.provider_assigned" and r[3] == bk["a10"]]
        assert len(assigned) == 1, kinds
        assert "Grace will arrive at 10 am." in assigned[0][2], assigned[0]
        assert not any("Gate code" in r[2] for r in alice_rows), "internal note reached the customer"
        # Alice's own reschedule and cancellation of a10 are not notified.
        assert not any(r[3] == bk["a10"] and r[0] in ("booking.rescheduled", "booking.cancelled") for r in alice_rows), kinds
        review = [r for r in alice_rows if r[0] == "hiring.under_review"]
        assert review and any("We are reviewing your request." in r[2] for r in review), kinds
        assert not any("Customer prefers Kenyan maids." in r[2] for r in alice_rows), "internal hiring note reached the customer"
        assert "hiring.shortlisted" in kinds and "enquiry.in_progress" in kinds, kinds
        enquiry = next(r for r in alice_rows if r[0] == "enquiry.in_progress")
        assert enquiry[5] == kenya, enquiry
        assert all(r[0] != "booking.pending" for r in alice_rows), "booking creation notified"

        # Bob: the agency cancelled b18 with a visible note.
        bob_rows = rows(bob)
        cancelled = [r for r in bob_rows if r[0] == "booking.cancelled" and r[3] == bk["b18"]]
        assert len(cancelled) == 1 and "Customer called to cancel." in cancelled[0][2], bob_rows

        # Staff reschedule and visible notes; customer's own changes stay silent.
        before = len(rows(bob))
        as_user(c, ben)
        try:
            c.execute("select public.update_booking_status(%s, 'confirmed', '', true)", (bk["b11"],))
            c.execute("select public.update_booking_status(%s, 'confirmed', 'Please keep the pets inside.', true)", (bk["b11"],))
            c.execute("select public.update_booking_status(%s, 'confirmed', 'Internal only.', false)", (bk["b11"],))
            c.execute("update public.bookings set starts_at=%s where id=%s", (at(15, days=1), bk["b11"]))
        finally:
            reset(c)
        new = rows(bob)[before:]
        assert [r[0] for r in new] == ["booking.confirmed", "booking.note", "booking.rescheduled"], new
        assert new[1][2] == "Please keep the pets inside." and new[1][3] == bk["b11"], new[1]
        assert new[2][2].startswith("Your ") and "03:00 PM." in new[2][2] and "Rescheduled to" not in new[2][2], new[2]

        # Customers see only their own, cannot write or fake them, and can only mark read.
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.customer_notifications where customer_id<>%s", (bob,)) == 0
            expect_denied(c, "insert into public.customer_notifications (customer_id, kind, title) values (%s, 'x.y', 'Fake')", (bob,))
            expect_denied(c, "update public.customer_notifications set title='Changed'")
            expect_denied(c, "delete from public.customer_notifications")
            expect_denied(c, "select private.notify_customer(%s, 'x.y', 'Fake', '')", (bob,))
            first = one(c, "select id from public.customer_notifications order by id limit 1")
            c.execute("select public.mark_customer_notifications_read(%s)", ([first],))
            assert one(c, "select count(*) from public.customer_notifications where read_at is not null") == 1
            c.execute("select public.mark_customer_notifications_read()")
            assert one(c, "select count(*) from public.customer_notifications where read_at is null") == 0
        finally:
            reset(c)
        assert one(c, "select count(*) from public.customer_notifications where customer_id=%s and read_at is null", (alice,)) > 0, \
            "Bob marked Alice's notifications as read"
        as_user(c, None)
        try:
            expect_denied(c, "select * from public.customer_notifications")
            expect_denied(c, "select public.mark_customer_notifications_read()")
        finally:
            reset(c)
    check("Customer notifications: agency updates notify the customer (own actions and internal notes never); customers read only theirs and can only mark them read", customer_notifications)

    # --- recruitment routes and customer documents --------------------------------
    class _Undo(Exception):
        pass

    def recruitment_routes():
        assert one(c, "select location from public.candidates where id=%s", (kenya,)) == "in_uae"
        as_user(c, None)
        try:
            assert one(c, "select count(location) from public.candidates") >= 0  # guests may read it
        finally:
            reset(c)
        # Arrival days: both or neither, From <= To, admins only.
        as_user(c, sam)
        try:
            expect_violation(c, "update public.maid_nationalities set arrival_days_min=20, arrival_days_max=10 where name='Kenya'")
            expect_violation(c, "update public.maid_nationalities set arrival_days_min=10 where name='Kenya'")
            expect_violation(c, "update public.maid_nationalities set arrival_days_min=0, arrival_days_max=10 where name='Kenya'")
            c.execute("update public.maid_nationalities set arrival_days_min=10, arrival_days_max=20 where name='Kenya'")
        finally:
            reset(c)
        assert c.execute("select arrival_days_min, arrival_days_max from public.maid_nationalities where name='Kenya'").fetchone() == (10, 20)
        as_user(c, rita)
        try:
            n = c.execute("update public.maid_nationalities set arrival_days_min=1, arrival_days_max=2 where name='Kenya' returning name").fetchall()
            assert n == [], "recruitment officers changed arrival times"
        finally:
            reset(c)
        # Requests keep the chosen maid's location; a recommendation keeps the customer's choice.
        try:
            with c.transaction():
                c.execute("update public.candidates set location='outside_uae', availability_status='available', is_published=true, archived_at=null where id=%s", (kenya,))
                as_user(c, alice)
                try:
                    picked = one(c, "insert into public.hiring_requests (package_id, duration_months, candidate_id, maid_location, customer_name, customer_phone, emirate) "
                                    "values (%s, 3, %s, 'in_uae', 'Alice Customer', '+971501234567', 'Dubai') returning maid_location", (monthly, kenya))
                    assert picked == "outside_uae", picked
                    chosen = one(c, "insert into public.hiring_requests (package_id, duration_months, maid_location, customer_name, customer_phone, emirate) "
                                    "values (%s, 3, 'outside_uae', 'Alice Customer', '+971501234567', 'Dubai') returning maid_location", (monthly,))
                    assert chosen == "outside_uae", chosen
                    expect_violation(c, "insert into public.hiring_requests (package_id, duration_months, maid_location, customer_name, customer_phone, emirate) "
                                        "values (%s, 3, 'mars', 'Alice Customer', '+971501234567', 'Dubai')", (monthly,))
                finally:
                    reset(c)
                raise _Undo()
        except _Undo:
            pass
    check("Recruitment routes: maid location (default in the UAE), arrival days per nationality (admins), requests keep the location", recruitment_routes)

    def customer_documents():
        path = alice + "/passport-1.pdf"
        as_user(c, alice)
        try:
            c.execute("insert into storage.objects (bucket_id, name) values ('customer-documents', %s)", (path,))
            expect_denied(c, "insert into storage.objects (bucket_id, name) values ('customer-documents', %s)", (bob + "/x.pdf",))
            expect_denied(c, "insert into public.customer_documents (customer_id, document_type, storage_path, file_name, mime_type, size_bytes) values (%s, 'passport', %s, 'p.pdf', 'application/pdf', 1000)", (bob, path))
            expect_denied(c, "insert into public.customer_documents (document_type, storage_path, file_name, mime_type, size_bytes, status) values ('passport', %s, 'p.pdf', 'application/pdf', 1000, 'approved')", (path,))
            expect_denied(c, "insert into public.customer_documents (document_type, storage_path, file_name, mime_type, size_bytes) values ('passport', %s, 'p.pdf', 'application/pdf', 1000)", (bob + "/x.pdf",))
            expect_violation(c, "insert into public.customer_documents (document_type, storage_path, file_name, mime_type, size_bytes) values ('passport', %s, 'p.exe', 'application/x-msdownload', 1000)", (path,))
            expect_violation(c, "insert into public.customer_documents (document_type, storage_path, file_name, mime_type, size_bytes) values ('passport', %s, 'p.pdf', 'application/pdf', 20000000)", (path,))
            doc = one(c, "insert into public.customer_documents (document_type, storage_path, file_name, mime_type, size_bytes) values ('passport', %s, 'passport.pdf', 'application/pdf', 1000) returning id::text", (path,))
            row = c.execute("select customer_id::text, status from public.customer_documents where id=%s", (doc,)).fetchone()
            assert row == (alice, "submitted"), row
            expect_denied(c, "update public.customer_documents set status='approved' where id=%s", (doc,))
        finally:
            reset(c)
        assert one(c, "select count(*) from public.staff_notifications where kind='document.uploaded'") == 1
        # Other customers and booking staff see nothing.
        for other in (bob, ben):
            as_user(c, other)
            try:
                assert one(c, "select count(*) from public.customer_documents") == 0
                assert one(c, "select count(*) from storage.objects where bucket_id='customer-documents'") == 0
                c.execute("delete from public.customer_documents")
                c.execute("delete from storage.objects where bucket_id='customer-documents'")
            finally:
                reset(c)
        assert one(c, "select count(*) from public.customer_documents where id=%s", (doc,)) == 1
        as_user(c, None)
        try:
            expect_denied(c, "select * from public.customer_documents")
        finally:
            reset(c)
        # Recruitment staff review: a reason is required to ask for a new copy.
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from storage.objects where name=%s", (path,)) == 1
            expect_violation(c, "update public.customer_documents set status='needs_new_copy' where id=%s", (doc,))
            expect_denied(c, "update public.customer_documents set storage_path=%s where id=%s", (rita + "/x.pdf", doc))
            c.execute("update public.customer_documents set status='needs_new_copy', staff_note='The photo page is blurred.' where id=%s", (doc,))
        finally:
            reset(c)
        row = c.execute("select status, reviewed_by::text, reviewed_at is not null from public.customer_documents where id=%s", (doc,)).fetchone()
        assert row == ("needs_new_copy", rita, True), row
        note = c.execute("select kind, body from public.customer_notifications where customer_id=%s and kind like 'document.%%' order by id desc limit 1", (alice,)).fetchone()
        assert note == ("document.needs_new_copy", "Your Passport copy needs a new copy: The photo page is blurred."), note
        # The customer replaces the file: back to review, note cleared, staff told again.
        as_user(c, alice)
        try:
            new_path = alice + "/passport-2.pdf"
            c.execute("insert into storage.objects (bucket_id, name) values ('customer-documents', %s)", (new_path,))
            c.execute("update public.customer_documents set storage_path=%s, file_name='passport-new.pdf', size_bytes=2000 where id=%s", (new_path, doc))
            c.execute("delete from storage.objects where bucket_id='customer-documents' and name=%s", (path,))
            row = c.execute("select status, staff_note, reviewed_by from public.customer_documents where id=%s", (doc,)).fetchone()
            assert row == ("submitted", "", None), row
        finally:
            reset(c)
        assert one(c, "select count(*) from public.staff_notifications where kind='document.uploaded'") == 2
        as_user(c, rita)
        try:
            c.execute("update public.customer_documents set status='approved', staff_note='' where id=%s", (doc,))
        finally:
            reset(c)
        assert one(c, "select kind from public.customer_notifications where customer_id=%s order by id desc limit 1", (alice,)) == "document.approved"

        # Accounts with documents are only deleted after the documents are removed.
        erin = new_user(c, "erin@example.com", "Erin Leaving")
        as_user(c, erin)
        try:
            epath = erin + "/emirates-1.png"
            c.execute("insert into storage.objects (bucket_id, name) values ('customer-documents', %s)", (epath,))
            c.execute("insert into public.customer_documents (document_type, storage_path, file_name, mime_type, size_bytes) values ('emirates_id', %s, 'eid.png', 'image/png', 500)", (epath,))
            ereq = one(c, "insert into public.account_deletion_requests (reason) values ('Bye') returning id::text")
        finally:
            reset(c)
        as_user(c, sam)
        try:
            try:
                with c.transaction():
                    c.execute("select public.process_account_deletion(%s)", (ereq,))
                raise AssertionError("account deleted while documents remained")
            except errors.CheckViolation as e:
                assert "documents first" in str(e), e
            c.execute("delete from storage.objects where bucket_id='customer-documents' and name like %s", (erin + "/%",))
            c.execute("delete from public.customer_documents where customer_id=%s", (erin,))
            c.execute("select public.process_account_deletion(%s)", (ereq,))
        finally:
            reset(c)
        assert one(c, "select count(*) from auth.users where id=%s", (erin,)) == 0
    check("Customer documents: private files in the customer's own folder; recruitment staff review (reason required) and the customer is notified; replacing sends it back; deletion waits for documents", customer_documents)

    # --- video interview ----------------------------------------------------------
    def video_interview():
        as_user(c, sam)
        try:
            expect_violation(c, "update public.candidates set video_id='https://youtu.be/abc' where id=%s", (kenya,))
            expect_violation(c, "update public.candidates set video_id='short' where id=%s", (kenya,))
            c.execute("update public.candidates set video_id='dQw4w9WgXcQ' where id=%s", (kenya,))
            try:
                with c.transaction():
                    c.execute("update public.candidates set has_video=false where id=%s", (kenya,))
                raise AssertionError("has_video was changed by hand")
            except errors.GeneratedAlways:
                pass
        finally:
            reset(c)
        assert one(c, "select has_video from public.candidates where id=%s", (kenya,)) is True
        # Any other https link goes in video_url (and also counts as a video).
        as_user(c, sam)
        try:
            for bad in ("http://gldws.ae/worker/video/612", "javascript:alert(1)", "https://bad link", "https://" + "a" * 500):
                expect_violation(c, "update public.candidates set video_url=%s where id=%s", (bad, kenya))
            c.execute("update public.candidates set video_id=null, video_url='https://gldws.ae/worker/video/612' where id=%s", (kenya,))
            assert one(c, "select has_video from public.candidates where id=%s", (kenya,)) is True
            c.execute("update public.candidates set video_url=null where id=%s", (kenya,))
            assert one(c, "select has_video from public.candidates where id=%s", (kenya,)) is False
            c.execute("update public.candidates set video_url='https://vimeo.com/76979871' where id=%s", (kenya,))
        finally:
            reset(c)
        as_user(c, None)
        try:
            assert one(c, "select video_url from public.candidates where id=%s", (kenya,)) in ("https://vimeo.com/76979871", None)
            expect_denied(c, "update public.candidates set video_url=null")
        finally:
            reset(c)
        as_user(c, sam)
        try:
            c.execute("update public.candidates set video_url=null, video_id='dQw4w9WgXcQ' where id=%s", (kenya,))
        finally:
            reset(c)
        as_user(c, None)
        try:
            assert one(c, "select count(*) from public.candidates where has_video") >= 0
            # The website plays interviews: guests read the video ID (published maids only)…
            assert one(c, "select video_id from public.candidates where id=%s", (kenya,)) in ("dQw4w9WgXcQ", None)
            # Religion is shown on the website's cards (agency's decision), published maids only…
            assert one(c, "select religion from public.candidates where id=%s", (kenya,)) == "Christian"
            # …but never the private details.
            for column in ("bio", "marital_status"):
                expect_denied(c, f"select {column} from public.candidates")
            expect_denied(c, "update public.candidates set video_id=null")
        finally:
            reset(c)
        as_user(c, alice)
        try:
            assert one(c, "select video_id from public.candidates where id=%s", (kenya,)) == "dQw4w9WgXcQ"
            n = c.execute("update public.candidates set video_id=null where id=%s returning id", (kenya,)).fetchall()
            assert n == [], "a customer changed a maid's video"
        finally:
            reset(c)
        as_user(c, sam)
        try:
            c.execute("update public.candidates set video_id=null where id=%s", (kenya,))
        finally:
            reset(c)
        assert one(c, "select has_video from public.candidates where id=%s", (kenya,)) is False
    check("Video interview: a YouTube video ID or any https video link can be saved, by staff; guests can read it (website player) but not change it, and still not the private details", video_interview)

    # --- hire cards ------------------------------------------------------------------
    def hire_route_cards():
        as_user(c, None)
        try:
            assert one(c, "select count(*) from public.hire_route_cards") == 2
            expect_denied(c, "update public.hire_route_cards set image_path='x.jpg'")
        finally:
            reset(c)
        for who in (alice, rita):
            as_user(c, who)
            try:
                n = c.execute("update public.hire_route_cards set image_path='hire/x.jpg' returning id").fetchall()
                assert n == [], "a non-admin changed a hire card photo"
                expect_denied(c, "insert into public.hire_route_cards (visa_type) values ('sponsor')")
                expect_denied(c, "delete from public.hire_route_cards")
            finally:
                reset(c)
        as_user(c, sam)
        try:
            c.execute("update public.hire_route_cards set image_path='hire/sponsor-1.jpg' where visa_type='sponsor'")
            expect_denied(c, "update public.hire_route_cards set visa_type='company' where visa_type='sponsor'")
        finally:
            reset(c)
        assert one(c, "select image_path from public.hire_route_cards where visa_type='sponsor'") == "hire/sponsor-1.jpg"
        assert one(c, "select count(*) from public.admin_audit_logs where action='hire_route_cards.updated'") >= 1
    check("Hire a Maid card photos: everyone reads them; only administrators change the photo", hire_route_cards)

    # --- wallet -------------------------------------------------------------------------
    def wallet():
        def balance(uid):
            as_user(c, uid)
            try:
                return one(c, "select public.my_wallet_balance()")
            finally:
                reset(c)

        assert balance(bob) == 0
        # Customers cannot write anything to their wallet.
        as_user(c, bob)
        try:
            expect_denied(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'credit', 'agency', 100, 100)", (bob,))
            expect_denied(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'top_up', 'card', 100, 100)", (bob,))
        finally:
            reset(c)
        # Recruitment staff are not administrators.
        as_user(c, rita)
        try:
            expect_denied(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'credit', 'agency', 50, 50)", (bob,))
        finally:
            reset(c)
        # An administrator adds a credit; the effect must match the amount.
        as_user(c, sam)
        try:
            expect_violation(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'credit', 'agency', 50, 500)", (bob,))
            expect_denied(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'top_up', 'card', 50, 50)", (bob,))
            expect_denied(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'credit', 'agency', 50, 50)", (sam,))
            ref = one(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect, description) values (%s, 'credit', 'agency', 50, 50, 'Sorry for the delay') returning reference", (bob,))
            assert ref.startswith("WT-"), ref
            # A correction cannot take the balance below zero.
            expect_violation(c, "insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'adjustment', 'agency', 80, -80)", (bob,))
            c.execute("insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect, description) values (%s, 'adjustment', 'agency', 20, -20, 'Correction')", (bob,))
            expect_denied(c, "update public.wallet_transactions set amount=1")
            expect_denied(c, "delete from public.wallet_transactions")
        finally:
            reset(c)
        assert balance(bob) == 30
        assert balance(alice) == 0
        note = c.execute("select kind, body from public.customer_notifications where customer_id=%s and kind like 'wallet.%%' order by id", (bob,)).fetchall()
        assert note[0] == ("wallet.credit", "AED 50.00 was added to your wallet: Sorry for the delay"), note
        assert note[1][0] == "wallet.adjustment", note
        # The server (payment gateway handler) records card payments.
        c.execute("insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect, card_brand, card_last4, gateway_reference, description) values (%s, 'payment', 'card', 120, 0, 'visa', '4242', 'gw_1', 'Home Cleaning')", (bob,))
        assert balance(bob) == 30
        try:
            with c.transaction():
                c.execute("insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'payment', 'wallet', 31, -31)", (bob,))
            raise AssertionError("paid more than the balance")
        except errors.CheckViolation:
            pass
        # Each customer sees only their own history; the gateway reference is hidden.
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.wallet_transactions") == 0
            expect_denied(c, "select gateway_reference from public.wallet_transactions")
        finally:
            reset(c)
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.wallet_transactions") == 3
        finally:
            reset(c)
        as_user(c, None)
        try:
            expect_denied(c, "select * from public.wallet_transactions")
            expect_denied(c, "select public.my_wallet_balance()")
            assert one(c, "select value::text from public.app_settings where key='wallet.top_up_enabled'") == "false"
            assert one(c, "select value::text from public.app_settings where key='payments.cards_enabled'") == "false"
        finally:
            reset(c)

        # Saved cards: the server adds them; customers read (no token), choose a default, remove.
        c.execute("insert into public.saved_cards (customer_id, brand, last4, exp_month, exp_year, gateway_token) values (%s, 'visa', '4242', 12, 2030, 'tok_a'), (%s, 'mastercard', '5555', 1, 2031, 'tok_b'), (%s, 'visa', '1111', 2, 2032, 'tok_c')", (bob, bob, alice))
        as_user(c, bob)
        try:
            expect_denied(c, "insert into public.saved_cards (customer_id, brand, last4, exp_month, exp_year, gateway_token) values (%s, 'visa', '4242', 1, 2030, 'x')", (bob,))
            expect_denied(c, "select gateway_token from public.saved_cards")
            assert one(c, "select count(*) from public.saved_cards") == 2
            card = one(c, "select id::text from public.saved_cards where last4='5555'")
            c.execute("select public.set_default_card(%s)", (card,))
            other = one(c, "select id::text from public.saved_cards where last4='4242'")
            c.execute("select public.set_default_card(%s)", (other,))
            assert one(c, "select last4 from public.saved_cards where is_default") == "4242"
            alices = None
        finally:
            reset(c)
        alices = one(c, "select id::text from public.saved_cards where customer_id=%s", (alice,))
        as_user(c, bob)
        try:
            try:
                with c.transaction():
                    c.execute("select public.set_default_card(%s)", (alices,))
                raise AssertionError("set another customer's card")
            except errors.NoDataFound:
                pass
            c.execute("delete from public.saved_cards where id=%s", (alices,))
            c.execute("delete from public.saved_cards where last4='5555'")
            assert one(c, "select count(*) from public.saved_cards") == 1
        finally:
            reset(c)
        assert one(c, "select count(*) from public.saved_cards where customer_id=%s", (alice,)) == 1

        # An account with money in the wallet is not deleted.
        fay = new_user(c, "fay@example.com", "Fay Credit")
        as_user(c, sam)
        try:
            c.execute("insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect) values (%s, 'credit', 'agency', 30, 30)", (fay,))
        finally:
            reset(c)
        as_user(c, fay)
        try:
            freq = one(c, "insert into public.account_deletion_requests (reason) values ('Bye') returning id::text")
        finally:
            reset(c)
        as_user(c, sam)
        try:
            try:
                with c.transaction():
                    c.execute("select public.process_account_deletion(%s)", (freq,))
                raise AssertionError("deleted an account with a balance")
            except errors.CheckViolation as e:
                assert "AED 30.00" in str(e), e
            c.execute("insert into public.wallet_transactions (customer_id, kind, method, amount, balance_effect, description) values (%s, 'adjustment', 'agency', 30, -30, 'Refunded by bank transfer')", (fay,))
            c.execute("select public.process_account_deletion(%s)", (freq,))
        finally:
            reset(c)
        # Her history is kept for the accounts, without her.
        assert one(c, "select count(*) from public.wallet_transactions where customer_id is null") == 2
    check("Wallet: customers only read their own history and balance; admins add credits/corrections (customer notified); balance never negative; history permanent; saved cards hide the token; deletion waits for an empty wallet", wallet)

    # --- visa applications -------------------------------------------------------
    def visa_applications():
        as_user(c, alice)
        try:
            rid = one(c, "insert into public.hiring_requests (package_id, duration_months, candidate_id, customer_name, customer_phone, emirate) values (%s, 2, %s, 'Alice Customer', '+971501234567', 'Dubai') returning id::text", (monthly, kenya))
            expect_denied(c, "select public.start_visa_application(%s)", (rid,))
        finally:
            reset(c)
        # Moving the request to visa processing starts the application.
        as_user(c, rita)
        try:
            c.execute("select public.update_hiring_status(%s, 'visa_processing')", (rid,))
            app = one(c, "select id::text from public.visa_applications where hiring_request_id=%s", (rid,))
            route = one(c, "select route from public.visa_applications where id=%s", (app,))
            steps = [r[0] for r in c.execute("select step from public.visa_application_steps where application_id=%s order by position", (app,)).fetchall()]
            assert steps == (["contract_signed", "status_change", "medical_test", "biometrics", "residence_visa", "emirates_id"]
                             if route == "in_country" else
                             ["contract_signed", "entry_permit", "flight_booked", "arrived", "medical_test", "biometrics", "residence_visa", "emirates_id"]), (route, steps)
            # Starting again returns the same one; the route can change before any step starts.
            assert one(c, "select public.start_visa_application(%s, 'abroad')::text", (rid,)) == app
            assert one(c, "select count(*) from public.visa_application_steps where application_id=%s", (app,)) == 8
            expect_violation(c, "select public.start_visa_application(%s, 'moon')", (rid,))
        finally:
            reset(c)
        assert one(c, "select count(*) from public.customer_notifications where customer_id=%s and kind='visa.started'", (alice,)) == 1
        # The customer reads her tracker but cannot change it.
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.visa_applications") == 1
            assert one(c, "select count(*) from public.visa_application_steps") == 8
            c.execute("update public.visa_application_steps set status='done' where application_id=%s", (app,))
            c.execute("update public.visa_applications set visa_expires_on='2030-01-01' where id=%s", (app,))
            expect_denied(c, "insert into public.visa_application_steps (application_id, step, position) values (%s, 'arrived', 9)", (app,))
        finally:
            reset(c)
        assert one(c, "select count(*) from public.visa_application_steps where application_id=%s and status<>'waiting'", (app,)) == 0
        assert one(c, "select visa_expires_on from public.visa_applications where id=%s", (app,)) is None
        for other in (bob, ben):
            as_user(c, other)
            try:
                assert one(c, "select count(*) from public.visa_applications") == 0
                assert one(c, "select count(*) from public.visa_application_steps") == 0
            finally:
                reset(c)
        as_user(c, None)
        try:
            expect_denied(c, "select * from public.visa_applications")
        finally:
            reset(c)
        # Staff move steps; a finished step gets today's date; the customer is told.
        as_user(c, rita)
        try:
            c.execute("update public.visa_application_steps set status='in_progress' where application_id=%s and step='contract_signed'", (app,))
            c.execute("update public.visa_application_steps set status='done', note='  Signed at Tadbeer.  ' where application_id=%s and step='contract_signed'", (app,))
            row = c.execute("select step_date is not null, note, updated_by::text from public.visa_application_steps where application_id=%s and step='contract_signed'", (app,)).fetchone()
            assert row == (True, "Signed at Tadbeer.", rita), row
            expect_violation(c, "update public.visa_applications set route='in_country' where id=%s", (app,))
            expect_violation(c, "update public.visa_application_steps set status='finished' where application_id=%s and step='entry_permit'", (app,))
        finally:
            reset(c)
        bodies = [r[0] for r in c.execute("select body from public.customer_notifications where customer_id=%s and kind='visa.step' order by id", (alice,)).fetchall()]
        assert bodies == ["Contract signed: in progress.", "Contract signed: done. Signed at Tadbeer."], bodies
        # Documents: staff upload into the application's folder; only the customer and staff read them.
        path = app + "/visa.pdf"
        as_user(c, rita)
        try:
            c.execute("insert into storage.objects (bucket_id, name) values ('visa-documents', %s)", (path,))
            expect_denied(c, "insert into public.visa_documents (application_id, document_type, storage_path, file_name, mime_type, size_bytes) values (%s, 'visa', %s, 'v.pdf', 'application/pdf', 100)", (app, rita + "/v.pdf"))
            expect_violation(c, "insert into public.visa_documents (application_id, document_type, storage_path, file_name, mime_type, size_bytes) values (%s, 'selfie', %s, 'v.pdf', 'application/pdf', 100)", (app, path))
            c.execute("insert into public.visa_documents (application_id, document_type, storage_path, file_name, mime_type, size_bytes) values (%s, 'visa', %s, 'visa.pdf', 'application/pdf', 100)", (app, path))
        finally:
            reset(c)
        assert one(c, "select body from public.customer_notifications where customer_id=%s and kind='visa.document'", (alice,)) == "Visa has been added to your visa application."
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.visa_documents") == 1
            assert one(c, "select count(*) from storage.objects where bucket_id='visa-documents'") == 1
            expect_denied(c, "insert into storage.objects (bucket_id, name) values ('visa-documents', %s)", (app + "/fake.pdf",))
            expect_denied(c, "insert into public.visa_documents (application_id, document_type, storage_path, file_name, mime_type, size_bytes) values (%s, 'visa', %s, 'x.pdf', 'application/pdf', 100)", (app, app + "/x.pdf"))
            c.execute("delete from public.visa_documents")
            c.execute("delete from storage.objects where bucket_id='visa-documents'")
        finally:
            reset(c)
        assert one(c, "select count(*) from public.visa_documents") == 1
        assert one(c, "select count(*) from storage.objects where bucket_id='visa-documents'") == 1
        as_user(c, bob)
        try:
            assert one(c, "select count(*) from public.visa_documents") == 0
            assert one(c, "select count(*) from storage.objects where bucket_id='visa-documents'") == 0
        finally:
            reset(c)
        # Expiry reminder: once per date, 7 days ahead; a new date gets a new reminder.
        as_user(c, rita)
        try:
            c.execute("update public.visa_applications set visa_expires_on=(now() at time zone 'Asia/Dubai')::date + 20 where id=%s", (app,))
        finally:
            reset(c)
        assert one(c, "select private.send_visa_expiry_reminders()") == 0
        as_user(c, rita)
        try:
            c.execute("update public.visa_applications set visa_expires_on=(now() at time zone 'Asia/Dubai')::date + 7 where id=%s", (app,))
        finally:
            reset(c)
        assert one(c, "select private.send_visa_expiry_reminders()") == 1
        assert one(c, "select private.send_visa_expiry_reminders()") == 0
        assert one(c, "select count(*) from public.customer_notifications where customer_id=%s and kind='visa.expiring'", (alice,)) == 1
        assert one(c, "select count(*) from public.staff_notifications where kind='visa.expiring'") == 1
        as_user(c, rita)
        try:
            c.execute("update public.visa_applications set visa_expires_on=(now() at time zone 'Asia/Dubai')::date + 3 where id=%s", (app,))
        finally:
            reset(c)
        assert one(c, "select private.send_visa_expiry_reminders()") == 1
        # Customers and guests cannot run the reminder job.
        as_user(c, alice)
        try:
            expect_denied(c, "select private.send_visa_expiry_reminders()")
        finally:
            reset(c)
    check("Visa applications: start at visa processing (route from where she is), fixed steps per route, staff move steps (customer told), route locked once started, private visa files staff upload and the customer reads, expiry reminder 7 days ahead once per date", visa_applications)

    # --- website articles (Insights) ---------------------------------------------
    def website_articles():
        body = "A paragraph long enough to pass the length check for an article body text."
        # Recruitment staff write a draft; the author is always the writer.
        as_user(c, rita)
        try:
            art = one(c, "insert into public.website_articles (slug, title_en, summary_en, body_en, author_id) values ('documents-for-a-maid-visa', 'Documents for a maid visa', 'Everything you need to sponsor a maid in the UAE.', %s, %s) returning id::text", (body, alice))
            assert one(c, "select author_id::text from public.website_articles where id=%s", (art,)) == rita
            # Staff cannot publish (insert or update).
            expect_violation(c, "insert into public.website_articles (slug, title_en, summary_en, body_en, status) values ('x-published', 'Title here', 'A summary long enough to pass.', %s, 'published')", (body,))
            expect_violation(c, "update public.website_articles set status='published' where id=%s", (art,))
            # Arabic is all-or-nothing.
            expect_violation(c, "update public.website_articles set title_ar='عنوان المقال' where id=%s", (art,))
            c.execute("update public.website_articles set title_en='Documents you need for a maid visa' where id=%s", (art,))
            c.execute("delete from public.website_articles where id=%s", (art,))
            assert one(c, "select count(*) from public.website_articles where id=%s", (art,)) == 1, "staff deleted an article"
        finally:
            reset(c)
        # Guests and customers see no drafts.
        for who in (None, alice):
            as_user(c, who)
            try:
                assert one(c, "select count(*) from public.website_articles") == 0
            finally:
                reset(c)
        # An admin publishes: the date is set; staff can no longer edit it.
        as_user(c, ada)
        try:
            c.execute("update public.website_articles set status='published' where id=%s", (art,))
            assert one(c, "select published_at is not null from public.website_articles where id=%s", (art,))
            assert one(c, "select author_id::text from public.website_articles where id=%s", (art,)) == rita
        finally:
            reset(c)
        as_user(c, rita)
        try:
            c.execute("update public.website_articles set title_en='Changed by staff' where id=%s", (art,))
            assert one(c, "select title_en from public.website_articles where id=%s", (art,)) == "Documents you need for a maid visa"
        finally:
            reset(c)
        # Guests read it, but not who wrote it.
        as_user(c, None)
        try:
            assert one(c, "select count(*) from public.website_articles") == 1
            assert one(c, "select slug from public.website_articles") == "documents-for-a-maid-visa"
            expect_denied(c, "select author_id from public.website_articles")
            expect_denied(c, "insert into public.website_articles (slug, title_en, summary_en, body_en) values ('guest-try', 'Title here', 'A summary long enough to pass.', %s)", (body,))
        finally:
            reset(c)
        # A customer cannot write.
        as_user(c, alice)
        try:
            assert one(c, "select count(*) from public.website_articles") == 1
            expect_violation(c, "insert into public.website_articles (slug, title_en, summary_en, body_en) values ('cust-try', 'Title here', 'A summary long enough to pass.', %s)", (body,))
        finally:
            reset(c)
        # A future publish date stays hidden until then.
        as_user(c, ada)
        try:
            c.execute("insert into public.website_articles (slug, title_en, summary_en, body_en, status, published_at) values ('coming-later', 'Coming later', 'A summary long enough to pass.', %s, 'published', now() + interval '1 day')", (body,))
        finally:
            reset(c)
        as_user(c, None)
        try:
            assert one(c, "select count(*) from public.website_articles") == 1
        finally:
            reset(c)
        # Pictures: staff upload; only admins delete; customers cannot upload.
        as_user(c, rita)
        try:
            c.execute("insert into storage.objects (bucket_id, name) values ('insight-images', 'covers/a.jpg')")
            c.execute("delete from storage.objects where bucket_id='insight-images'")
        finally:
            reset(c)
        assert one(c, "select count(*) from storage.objects where bucket_id='insight-images'") == 1, "staff deleted a picture"
        as_user(c, alice)
        try:
            expect_denied(c, "insert into storage.objects (bucket_id, name) values ('insight-images', 'covers/b.jpg')")
        finally:
            reset(c)
        as_user(c, ada)
        try:
            c.execute("delete from storage.objects where bucket_id='insight-images'")
            c.execute("delete from public.website_articles where slug='coming-later'")
        finally:
            reset(c)
        assert one(c, "select count(*) from storage.objects where bucket_id='insight-images'") == 0
        assert one(c, "select count(*) from public.admin_audit_logs where entity_type='website_articles'") >= 5
    check("Website articles: staff write drafts (author fixed), admins publish/delete, guests read published only (not the author), Arabic all-or-nothing, cover pictures staff upload / admins delete", website_articles)

    # --- website enquiries (public enquiry form) ----------------------------------
    def website_enquiries():
        live_code = one(c, "select code from public.candidates where is_published and archived_at is null order by code limit 1")
        submit = ("select public.submit_website_enquiry(p_name=>%s, p_phone=>%s, p_need=>%s, p_emirate=>%s, "
                  "p_candidate_code=>%s, p_message=>%s, p_lang=>'en', p_page=>'/en/hire/', p_consent=>%s)")
        # A visitor sends an enquiry and only gets its reference back.
        as_user(c, None)
        try:
            ref = one(c, submit, ("  Fatima Ali ", "050 123 4567", "nanny", "dubai", live_code.lower(), " Two children ", True))
            assert ref.startswith("WE-"), ref
            # …but can never read, change or delete enquiries, or write to the table directly.
            expect_denied(c, "select * from public.website_enquiries")
            expect_denied(c, "update public.website_enquiries set status='closed'")
            expect_denied(c, "delete from public.website_enquiries")
            expect_denied(c, "insert into public.website_enquiries (reference, name, phone) values ('X', 'Bot', '123456789')")
            # Checks: consent, phone, allowed values.
            expect_violation(c, submit, ("Fatima", "0501234567", "nanny", "dubai", None, None, False))
            expect_violation(c, submit, ("Fatima", "12", "nanny", "dubai", None, None, True))
            expect_violation(c, submit, ("Fatima", "0509999999", "astronaut", "dubai", None, None, True))
            expect_violation(c, submit, ("Fatima", "0509999998", "nanny", "london", None, None, True))
            expect_violation(c, submit, ("F", "0509999997", "nanny", "dubai", None, None, True))
            # Same phone: at most 3 an hour.
            for _ in range(2):
                one(c, submit, ("Fatima Ali", "+971 50 123 4567", "nanny", "dubai", None, None, True))
            expect_violation(c, submit, ("Fatima Ali", "00971501234567", "nanny", "dubai", None, None, True))
        finally:
            reset(c)
        row = c.execute("select name, phone, need, candidate_id is not null, candidate_code, message, status from public.website_enquiries where reference=%s", (ref,)).fetchone()
        assert row == ("Fatima Ali", "+971501234567", "nanny", True, live_code.upper(), "Two children", "new"), row
        assert one(c, "select count(*) from public.staff_notifications where kind='website_enquiry.created'") >= 1
        # A signed-in customer can submit too, but cannot read the list.
        as_user(c, alice)
        try:
            one(c, submit, ("Alice", "0521112222", "housemaid", None, None, None, True))
            assert one(c, "select count(*) from public.website_enquiries") == 0
        finally:
            reset(c)
        # Recruitment staff read all and update status and note only.
        as_user(c, rita)
        try:
            assert one(c, "select count(*) from public.website_enquiries") >= 4
            c.execute("update public.website_enquiries set status='in_progress', staff_note='Called back' where reference=%s", (ref,))
            expect_denied(c, "update public.website_enquiries set phone='000' where reference='" + ref + "'")
        finally:
            reset(c)
        assert one(c, "select status from public.website_enquiries where reference=%s", (ref,)) == "in_progress"
    check("Website enquiries: visitors submit through one function and get only a reference; checks and limits; no reading; staff manage status and notes", website_enquiries)

    # --- report ------------------------------------------------------------------
    c.close()
    print()
    for ok, name, msg in results:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"\n        -> {msg}" if msg else ""))
    passed = sum(ok for ok, _, _ in results)
    print(f"\n{passed}/{len(results)} security tests passed")
    with admin_conn() as cc:
        cc.execute(f"drop database if exists {DB}")
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
