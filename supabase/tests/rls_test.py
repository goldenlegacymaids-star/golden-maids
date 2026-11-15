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
        results.append((False, name, str(e)))
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
    raise AssertionError(f"expected rejection, but it succeeded: {sql}")


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
