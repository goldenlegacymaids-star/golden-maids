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
| `hiring_requests` | Customer hiring requests (reference `HR-2026-000001`), validated against the package; customers can only cancel before processing |
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
| Text styles | `AppTypography` (Poppins headings, Inter body; fonts bundled in `assets/fonts/`) |
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

## ⚠️ Before store release (checklist)

- [ ] **Replace the onboarding photos** in `assets/images/onboarding/` with licensed stock or the client's own photo-shoot images (same file names, portrait, at least 1080 × 1440 px). The current images are temporary and their licence is unconfirmed. The banner candidates in `design/photos/` need the same treatment.
- [ ] Custom SMTP with the client's domain, and email templates ([guide](docs/supabase_auth_setup.md)).
- [ ] Meta Business Verification + WhatsApp sender connected to Twilio Verify.
- [ ] Delete or change the password of the test account `goldenmaids@gmail.com`.
- [ ] **Delete the 3 TEST candidates** (`delete from public.candidates where is_test;`) and their avatars in `candidate-photos/test/`.
- [ ] Candidate consent (UAE PDPL): every real candidate needs a recorded consent date before publishing (enforced by the database).
- [ ] In-app account deletion (store requirement); hiring requests are kept for records, so define the retention rule with the client.
- [ ] Nurse / Home Caregiver: confirm the client's healthcare licensing before showing these categories.
- [ ] Android release signing config (currently debug keys).
- [ ] Privacy policy and terms URLs.

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
| 2.3 | Candidate profile, favourites, Contact Agency | ⏳ Next |
| 2.4 | Hiring workflow + My Hiring Requests | Planned |
