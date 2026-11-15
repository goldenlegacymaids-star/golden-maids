# Golden Maids – Staff website

Website for Golden Legacy Domestic Workers Services staff (Super
Administrators, Administrators and Recruitment Officers). Built with
Next.js 16 (static export), TypeScript, Tailwind CSS and Supabase.

It uses the **same Supabase project** as the mobile app. Access is decided
by the database (Row Level Security), so the website only ever uses the
**publishable key** – never the `service_role` / secret key.

## First-time setup (Windows, PowerShell)

1. Install **Node.js LTS** from <https://nodejs.org> (version 22 or newer),
   then close and reopen PowerShell. Check: `node --version`
2. Go to the folder and install the packages:

   ```
   cd admin
   npm install
   ```

3. Create the settings file and fill in the values from Supabase →
   Project Settings → API (the same values as the app's `env.json`):

   ```
   copy .env.example .env.local
   notepad .env.local
   ```

   `.env.local` is ignored by Git – never commit it.

## Run on your computer

```
npm run dev
```

Open <http://localhost:3000> and sign in with a staff account.

## Check before pushing

```
npm run check
```

Runs type checking, linting, unit tests and a production build.

## Staff accounts

1. The person signs up in the **Golden Maids app** (email + password) and
   verifies their email.
2. A Super Administrator gives them a role (Recruitment Officer,
   Administrator…). Until a role-management page exists, roles are granted
   with SQL by the developer.
3. Accounts without a staff role are refused and signed out.

## Build for hosting

```
npm run build
```

Creates the `out/` folder (plain HTML/CSS/JS) for any static host. Hosting
is chosen before launch.

## Steps

| Step | Content | Status |
|---|---|---|
| A.1 | Sign-in with role check, layout, dashboard | ✅ Done |
| A.2 | Hiring requests and enquiries | ⏳ Next |
| A.3 | Candidates (create/edit, photos, documents, publish) | Planned |
| A.4 | Prices and offers | Planned |
