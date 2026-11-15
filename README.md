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

Role checks used by policies live in the private schema: `private.has_role()`, `private.has_any_role()`, `private.is_admin()`, `private.is_staff()`.

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
| 1.4 | Splash + onboarding | ⏳ Next |
| 1.5 | Authentication | — |
| 1.6 | Bottom navigation + app shell | — |
| 1.7 | Home screen + service categories | — |
