# Supabase Auth setup – Golden Maids

Project: **Golden Maids** (`scelzzqsweufyinphxwa`) → <https://supabase.com/dashboard/project/scelzzqsweufyinphxwa>

These settings live in the Supabase dashboard (they are not SQL migrations). Apply them in order. Items marked **[Launch]** can wait until before release.

---

## 1. Email sign-up and passwords

**Authentication → Sign In / Providers → Email**

| Setting | Value |
|---|---|
| Enable Email provider | On |
| Confirm email | **On** |
| Secure email change | On |
| Minimum password length | **8** |
| Password requirements | **Letters and digits** |
| Email OTP length | **6** |
| Email OTP expiration | **600** seconds (10 minutes) |

## 2. Email templates (6-digit codes instead of links)

**Authentication → Emails → Templates**. The app asks users to type a 6-digit code, so each template must show `{{ .Token }}`.

### Confirm signup
Subject: `Your Golden Maids verification code`
```html
<h2>Welcome to Golden Maids</h2>
<p>Your verification code is:</p>
<p style="font-size:28px;font-weight:600;letter-spacing:6px">{{ .Token }}</p>
<p>Enter this code in the app to confirm your email. It expires in 10 minutes.</p>
<p>If you didn't create a Golden Maids account, you can ignore this email.</p>
```

### Reset password
Subject: `Your Golden Maids password reset code`
```html
<h2>Reset your password</h2>
<p>Your password reset code is:</p>
<p style="font-size:28px;font-weight:600;letter-spacing:6px">{{ .Token }}</p>
<p>Enter this code in the app to choose a new password. It expires in 10 minutes.</p>
<p>If you didn't ask to reset your password, you can ignore this email.</p>
```

> If the dashboard does not allow editing templates on the default email service, complete step 4 (custom SMTP) first.

## 3. Phone sign-in (WhatsApp codes)

WhatsApp codes require **Twilio Verify** with the client's own WhatsApp Business sender (after Meta Business Verification).

**Until then (development):**
1. Create a free Twilio account and a **Verify Service** (Twilio Console → Verify → Services).
2. **Authentication → Sign In / Providers → Phone**: enable, provider **Twilio Verify**, enter Account SID, Auth Token and Verify Service SID.
3. Turn **off** "Enable phone confirmations" only if asked; keep phone sign-ups **enabled**.
4. Add **Test Phone Numbers and OTPs**, e.g.
   `971500000001=123456, 971500000002=123456`
   These never send real messages; type the number as `50 000 0001` in the app and the code `123456`.

**[Launch]** After Meta verification: create the WhatsApp sender in Twilio, connect it to the Verify Service's messaging service, and test with a real number.

**SMS fallback** (optional, later): once an SMS sender ID is registered for the UAE, an admin sets `auth.sms_fallback_enabled` to `true` in `public.app_settings`. The app then shows "Send by SMS instead" with no update needed.

## 4. **[Launch]** Custom SMTP (required for real users)

The built-in email service only delivers to members of the Supabase team and is heavily rate-limited.

1. Create an account with a transactional email provider (e.g. Resend or Brevo).
2. Verify the client's domain (DNS records: SPF, DKIM).
3. **Authentication → Emails → SMTP Settings**: enable custom SMTP, sender `no-reply@<domain>`, sender name `Golden Maids`.
4. **Authentication → Rate Limits**: raise the email limit to match the provider plan.

## 5. **[Launch]** Abuse protection
- **Authentication → Rate Limits**: review OTP and sign-in limits.
- Consider CAPTCHA (hCaptcha / Cloudflare Turnstile) on sign-up if abuse appears.

## Testing now (before SMTP)
Email sign-up and password reset emails reach **only Supabase team members**. Test with an email address that is a member of the Supabase organisation.
