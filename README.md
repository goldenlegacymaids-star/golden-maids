# Golden Maids

**Professional Care. Trusted Homes.**

Golden Maids is a domestic workforce recruitment and home-services app for the UAE, operated by **Golden Legacy Domestic Workers Services**.

- **App:** Flutter (Android, iOS, web)
- **Backend:** Supabase project `Golden Maids` (`scelzzqsweufyinphxwa`), region `ap-south-1` (Mumbai)
- **App ID:** `com.goldenmaids.app`

---

## Requirements

- Flutter stable **3.44 or newer** (Dart **3.12+**). Check with `flutter --version`.
- Android Studio (Android) and/or Xcode on macOS (iOS).

## First-time setup

```bash
git clone https://github.com/goldenlegacymaids-star/golden-maids.git
cd golden-maids
flutter pub get
```

Create your local settings file from the template:

```bash
cp env.example.json env.json      # macOS / Linux
copy env.example.json env.json    # Windows
```

`env.json` is git-ignored and must **never** be committed. Fill in:

| Key | Value |
|---|---|
| `SUPABASE_URL` | Project URL (Supabase → Project Settings → API) |
| `SUPABASE_PUBLISHABLE_KEY` | The **publishable** key (`sb_publishable_...`) |

## Run

```bash
flutter run --dart-define-from-file=env.json
```

## Check before every commit

```bash
flutter analyze   # must report "No issues found!"
flutter test      # all tests must pass
```

## Database

Schema changes are made **only** through SQL migrations in `supabase/migrations/` (file names match the versions recorded in Supabase). Every table has Row Level Security enabled.

| Table | Purpose |
|---|---|
| `roles` | The 8 roles (Super Admin … Customer) |
| `user_roles` | Role assignments. Only admins grant roles; only super admins manage admin roles; changes are audit-logged |
| `profiles` | One per user, created automatically on sign-up with the Customer role |
| `addresses` | Saved customer addresses (UAE emirates validated, GCC-ready) |
| `admin_audit_logs` | Append-only audit trail of administrative actions |
| `app_settings` | Remote switches (e.g. `auth.sms_fallback_enabled`); admins edit values only, audit-logged |
| `service_categories` | Home-service categories (11) – public read, admin-managed |
| `services` | Services (20) – **prices set by admins** (null = "Price on request") |
| `promotions` | Home banners/offers with optional `discount_percent`, start/end dates – admin-managed |
| Storage `app-media` | Public images (categories, services, banners); admin upload only |
| `recruitment_packages` | Hiring packages: Live-In Monthly (1–11 months) and Yearly (12 or 24 months) on the company visa; 2-Year Contract on a GCC sponsor visa – **prices set by admins** |
| `candidates` | Worker profiles as shown to customers (code `GM-00001`, nationality, age, skills…). **Guests see card columns only**; signed-in users see the full profile; the name is shown only when an admin allows it |
| `candidate_private_details` | Full name, date of birth, passport number, internal notes – **recruitment staff only**. Age is computed from it (trigger + daily job) |
| `candidate_skills` / `_languages` / `_experience` / `_packages` | Profile details; work history is for signed-in users only |
| `candidate_documents` | Documents in the private bucket. Passport, visa and medical documents can **never** be shown to customers |
| `candidate_favourites` | Each customer's saved candidates (private) |
| `candidate_enquiries` | "Request Info" messages about a candidate (reference `EQ-2026-000001`); customers send and see their own (no edits), recruitment staff manage status; max 5 per customer per hour |
| `bookings` / `booking_history` | Home-service bookings (reference `BK-2026-000001`), price estimate, address snapshot, status timeline; customers cancel/reschedule until 24 h before, booking staff manage all |
| `service_staff` (+ `_private`, `_categories`) | The agency's staff who do home services; customers see only the staff assigned to their booking |
| `booking_settings` | Working hours, slot length, min/max hours, notice, window, cancellation limit (admins) |
| `staff_notifications` / `staff_notification_reads` | The staff website's bell: triggers add a notification when, in the app, a booking is made / cancelled / rescheduled, a hiring request is sent / cancelled, an enquiry arrives, account deletion is requested / withdrawn, or a customer signs up. Staff see only their area's notifications (bookings, recruitment, admin); read status is per person; streamed live with Supabase Realtime |
| `account_deletion_requests` | Customers request deletion of their own account (optional reason) and may withdraw it while pending; only admins see all and mark them completed (who/when recorded). Kept as a record after the account is deleted. Admins process a request with `process_account_deletion()` (staff website): sign-in, profile, addresses, saved maids and enquiries are removed; bookings and hiring requests are kept without name, phone, email, building or notes; audit-logged. Refused while bookings/hiring requests are open or the user has staff roles |
| `maid_nationalities` | Nationalities of maids (name + ISO code for the flag), managed by admins: add, rename (follows through), order, hide; can't delete one in use |
| `recruitment_package_prices` | Package prices per maid nationality, for packages with `price_by_nationality` (the 2-Year GCC Sponsor package: one-off recruitment cost). No row = price on request |
| `hiring_requests` | Customer hiring requests (reference `HR-2026-000001`), validated against the package; keep the maid nationality and the price quoted at submission; customers can only cancel before processing |
| `hiring_request_history` | Status timeline; internal notes hidden from customers |
| Storage `candidate-photos` / `candidate-documents` | Public candidate photos / **private** documents; recruitment staff upload only |

Admin changes to categories, services and promotions are written to `admin_audit_logs` automatically.

Role checks used by policies live in the private schema: `private.has_role()`, `private.has_any_role()`, `private.is_admin()`, `private.is_staff()`, `private.is_recruitment_staff()`.

Hiring statuses: `submitted` → `under_review` → `shortlisted` → `interview_scheduled` → `offer_accepted` → `visa_processing` → `completed` (or `cancelled` / `rejected`).

**Security tests:** `supabase/tests/rls_test.py` builds a local PostgreSQL database from the migrations and checks what guests, customers, admins and staff can and cannot do. Run it after any database change (requires a local PostgreSQL 16+ and `pip install "psycopg[binary]"`):

```bash
python3 supabase/tests/rls_test.py
```

## Design system

All UI must use the shared design system. Do not hard-code colours, fonts or sizes in screens.

| Need | Use |
|---|---|
| Colours | `AppColors` (`lib/core/theme/app_colors.dart`) |
| Text styles | `AppTypography` (Outfit for headings and body; bundled in `assets/fonts/` with its OFL licence) |
| Spacing / radius / shadows | `AppSpacing`, `AppRadius`, `AppShadows` |
| Buttons | `AppButton` (blocks repeat taps while an action runs), `AppIconButton` |
| Inputs | `AppTextField`, `AppSearchBar`, `AppChip` |
| Layout | `AppCard`, `SectionHeader` |
| Images | `AppNetworkImage` (cached, skeleton placeholder, fallback), `AppLogo` |
| States | `Skeleton`/`SkeletonBox`, `EmptyState`, `ErrorState` + `AppFailure` |

The **Option A "Sparkle Home"** logo is in `assets/images/` (PNG at 1x/2x/3x, colour and white versions) with master SVGs in `design/logo/`.

## Authentication

- **WhatsApp code** (Twilio Verify) or **email + password** (6-digit email codes), password reset, guest browsing.
- Dashboard settings and email templates: see [`docs/supabase_auth_setup.md`](docs/supabase_auth_setup.md).

## Navigation

Guests can browse candidate cards (*Featured Maids*, *Find a Maid*); opening a full profile asks them to sign in.

Four tabs in a floating bottom bar (`StatefulShellRoute`): each keeps its own state. Guests can browse; Bookings, Wallet and account pages show a sign-in prompt. Profile items for features not yet built are labelled **"Coming soon"** and are not tappable until their phase is delivered.

## App icons

All launcher icons and launch images (Android, iOS, web) are generated from the logo:

```bash
python3 design/tools/generate_app_icons.py   # needs rsvg-convert + ImageMagick
```

## 📌 Pending items

| # | Item | Status |
|---|---|---|
| **1** | Replace onboarding (and banner) photos with licensed or own photo-shoot images | Before store release |
| **2** | Supabase Auth setup ([guide](docs/supabase_auth_setup.md) §1–3: email settings + templates, Twilio Verify + test numbers) and a live sign-in test, then verify the profile + Customer role were created | To revisit |
| **3** | Push notifications to the phone (lock screen) for the same updates: needs the client's Firebase project, then a Supabase Edge Function with the Firebase key entered as a secret in the Supabase dashboard | Later |

## ⚠️ Before store release (checklist)

- [ ] **Replace the onboarding photos** in `assets/images/onboarding/` with licensed stock or the client's own photo-shoot images (same file names, portrait, at least 1080 × 1440 px). The current images are temporary and their licence is unconfirmed. The banner candidates in `design/photos/` need the same treatment.
- [ ] Custom SMTP with the client's domain, and email templates ([guide](docs/supabase_auth_setup.md)).
- [ ] Meta Business Verification + WhatsApp sender connected to Twilio Verify.
- [ ] Delete or change the password of the test account `goldenmaids@gmail.com`.
- [ ] **Delete the 3 TEST candidates** (`delete from public.candidates where is_test;`) and their avatars in `candidate-photos/test/`.
- [ ] Candidate consent (UAE PDPL): every real candidate needs a recorded consent date before publishing (enforced by the database).
- [ ] **Account deletion requests** (Profile → Delete my account) are saved for admins. Before release: the staff website page to process them, the step that removes the sign-in and personal details while keeping anonymised bookings and hiring requests, and the client's retention rule.
- [ ] Confirm the agency number **+971 4 323 4393 is registered on WhatsApp Business** (used by the WhatsApp button); contact details are in `lib/core/constants/agency_contact.dart`.
- [ ] Nurse / Home Caregiver: confirm the client's healthcare licensing before showing these categories.
- [ ] Android release signing config (currently debug keys).
- [ ] **Privacy Policy and Terms** are basic drafts in `lib/features/support/domain/legal_texts.dart` (shown with a "Draft" label). The client reviews them (with legal advice), then set `LegalTexts.isDraft = false`; the stores also need both as public web pages (URLs).

## Staff website

The staff website is a **separate Next.js project** (`golden-maids-admin`, delivered as a zip with its own README). It uses the same Supabase project with the publishable key only.

## Security rules

- Only the Supabase **project URL** and **publishable key** may appear in `env.json`. They are safe in the app because every table is protected by Row Level Security.
- **Never** put the Supabase `service_role` key, payment-gateway secrets or any other secret in the app, in `env.json` or in Git. Secrets belong in Supabase Edge Function secrets.

## Project structure

```
lib/
  main.dart            # entry point only
  app.dart             # root widget: theme + router
  core/
    config/            # build-time settings (env.dart)
    constants/         # app-wide constants and asset paths
    errors/            # AppFailure: user-friendly error types
    theme/             # colours, typography, spacing, radius, shadows, theme
    routing/           # GoRouter setup and route names
    network/           # API clients
    services/          # shared services
    utils/             # helpers
    widgets/           # shared UI components
  features/            # one folder per feature module
    onboarding/  authentication/  home/  services/  recruitment/
    candidates/  candidate_details/  hiring/  bookings/  visa/
    contracts/  wallet/  payments/  notifications/  profile/  support/
  models/
  repositories/
assets/
  images/  icons/  banners/  fonts/
design/
  logo/                # master logo SVGs (not bundled in the app)
```

Each feature is split into `presentation/`, `domain/` and `data/` folders as it is built.

## Build progress

| Step | Description | Status |
|---|---|---|
| 1.1 | Project skeleton, packages, folder structure, app ID | ✅ Done |
| 1.2 | Design system (colours, fonts, components) + logo | ✅ Done |
| 1.3 | Supabase connection + core database (profiles, roles, addresses, RLS) | ✅ Done |
| 1.4 | App name + icons, launch screens, splash, onboarding | ✅ Done |
| 1.5 | Authentication (WhatsApp code, email + password, reset, guest) | ✅ Done |
| 1.6 | App shell: bottom navigation (Home, Bookings, Wallet, Profile), profile + edit name | ✅ Done |
| 1.7 | Home screen: location, search, banners, categories, popular services; category, service details, search, notifications | ✅ Done |
| 2.1 | Recruitment database: packages, candidates, favourites, hiring requests, private storage, 3 TEST candidates | ✅ Done |
| 2.2 | Candidate directory (*Find a Maid*: search, nationality, job type, package, skills, availability, sort) + *Featured Maids* on Home | ✅ Done |
| 2.3 | Candidate profile, favourites (Saved Maids), Contact Agency (call, WhatsApp, email), Request Info | ✅ Done |
| 2.4 | Hiring workflow (company visa monthly/yearly, 2-year GCC sponsor with nationality, maid choice or agency recommendation, review, reference) + My Hiring Requests (status timeline, cancel before shortlisting) | ✅ Done |
| A.1 | **Staff website** (separate Next.js project, delivered as a zip): staff sign-in with role check, dashboard | ✅ Done |
| A.2–A.4 | Staff website: requests & enquiries, candidates, prices & offers | ✅ Done |
| 3.1 | **Bookings database**: booking types (hourly / visit / request), slots 8 am–8 pm daily, 2–8 h, exact staff capacity (no double-booking), free cancel/reschedule until 24 h before, timeline, pay on completion | ✅ Done |
| 3.2 | **Booking flow in the app**: Book now on service details (guests asked to sign in; 2-Year Maid Visa opens the hiring form), hours, day strip, free slots (UAE time), saved or new address (optional save), instructions, price estimate, pay on completion (cash or card), BK reference | ✅ Done |
| 3.3 | **My Bookings**: Upcoming / Active / Completed / Cancelled tabs, details (assigned professional, price, payment, address), status timeline, free cancel (optional reason) and reschedule until 24 h before; after that, call the agency | ✅ Done |
| 3.4 | Staff website A.5: bookings, service staff, booking settings | ✅ Done |
| 4.1 | **Profile essentials**: Saved Addresses (add, edit, delete, default), Help Centre (FAQ from the live booking rules + call, WhatsApp, email), draft Privacy Policy and Terms, Delete my account (request for admins; withdraw while pending) | ✅ Done |
| 4.2 | **Nationalities & 2-Year prices**: nationalities loaded from the database (Madagascar added; admins can add more), flags instead of the globe (bundled in `assets/flags/`, public domain), 2-Year GCC Sponsor price per maid nationality ("From AED …" until a nationality is known), customers choose a nationality when the agency recommends; requests show the nationality and the quoted price | ✅ Done |
| 4.3 | **Customer notifications (in-app)**: the database notifies customers when the agency changes a booking (confirmed, professional assigned, on the way, started, completed, cancelled, rescheduled), a hiring request (each status) or an enquiry, or adds a note visible to the customer (internal notes and the customer's own actions never); Home bell with unread dot, live list (Realtime), tap to open the booking / request / maid, mark all read; Profile → Notifications opens the list | ✅ Done |
| 4.4 | **Recruitment routes + My Documents**: Home starts with *Hire a Maid* (GCC Sponsor Visa / Company Visa, each In the UAE or Outside the UAE); the maid list has visa chips and an In / Outside the UAE switch; badges show *Available now*, *From [date]* or *Arrives in X–Y days* (arrival days per nationality, set by admins); maid profiles show where she is; when the agency recommends, the customer chooses In / Outside the UAE; requests keep the location. **My Documents** (Emirates ID, passport copy, salary certificate, marriage certificate): upload a PDF/JPG/PNG up to 10 MB (private storage), view, replace, delete; the agency approves or asks for a new copy (with a reason) and the customer is notified; the GCC Sponsor review lists the documents. Migration `20261116180516_recruitment_routes_documents` (59/59 local security tests) | ✅ Done |
