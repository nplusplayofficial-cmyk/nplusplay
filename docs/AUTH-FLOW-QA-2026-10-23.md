# N+ PLAY authentication QA — 2026-10-23

## Status
**Code review and read-only DB assertions passed; full Work #3 is not closed yet.** No production accounts, passwords, wallet balances, auth settings, CAPTCHA secrets, or schema were changed. Real OTP/reset email delivery and Turnstile secret rotation could not be tested from the connected tools.

## Code fix staged
Main's `core/nplus-auth.js` had a defect in `sendSignupOtp()`: its immediate-session path referenced `cleanReferralCode` without declaring it. That path would throw when Supabase returns a session immediately. Branch `fix/auth-flow-qa-2026-10-23` now:
- Accepts and normalizes `referralCode` in `sendSignupOtp()`.
- Enforces the 16-character referral-code limit and the shared 12–128 character password length rule.
- Updates `auth.html`'s Auth script cache-busting value so clients load the candidate fix.
- Clears the password input and pending signup object's password as soon as Supabase accepts the signup request, so the OTP stage does not retain the password needlessly.

Static checks confirm the new declaration is before use, the password limit is present, the auth page points to the new cache key, the email OTP path uses `verifyOtp(type: "email")`, and the current main auth code does not call `nplus_phone_is_registered`.

Candidate code is NOT merged or deployed. Test the branch before merging.

## Live read-only evidence
- Auth users: 5; email confirmed: 5; unconfirmed: 0.
- Profiles: 5; demo wallets: 5; wallet-transaction rows: 146.
- Auth users missing a profile: 0; profiles missing a wallet: 0.
- `auth.users` creation trigger `on_auth_user_created_nplus` is present. `create_nplus_profile()` creates the profile and initial demo wallet; the profile trigger adds referral/VIP/safe-balance records.
- Normalized-phone unique index `profiles_phone_digits_unique_idx` is present and unique.
- Old phone-existence function `nplus_phone_is_registered(text)` still exists, but EXECUTE is denied to `anon` and `authenticated`. Keep it locked; do not drop it ad hoc before migration reconciliation.
- `core/nplus-captcha.js` has the public Turnstile site key, not a secret key.
- Supabase Security Advisor still flags leaked-password protection as disabled. The supplied handover says this is a Pro-plan feature; don't upgrade the Free project automatically. Keep the 12-character client policy and verify the server-side minimum in Dashboard.
- Read-only assertions in `qa/test-auth-security-contract.sql` were executed against live catalog/invariants without errors. They did not send test emails or create accounts.

## Reviewed Auth flow
- Signup submits a CAPTCHA token and supports either an OTP-confirmation response or a session response.
- Email OTP uses Supabase's `verifyOtp`; resend requires a fresh CAPTCHA and handles rate-limit errors.
- Login uses `signInWithPassword` with CAPTCHA and verifies the account's email/mobile against its profile.
- Password recovery requests a CAPTCHA-protected reset email, requires a recovery session before changing the password, applies the 12–128 mixed-character rule, then signs out the local recovery session.
- DB trigger/aggregate checks show no orphaned Auth users/profiles/wallets at audit time.

## Remaining acceptance gates
1. Using an owner-controlled test inbox and new test phone, signup, receive OTP, reject wrong/expired OTP, verify correct OTP, and confirm exactly one profile plus one starting wallet are created.
2. Verify duplicate normalized phone rejection, correct/incorrect login, sign-out and protected-page behavior.
3. Request password reset; check the actual production redirect URL, test invalid/expired link rejection, update password successfully, then verify new password works and old password fails.
4. In Supabase Dashboard, confirm Email Confirm setting, server-side password policy, CAPTCHA enabled, and allowed redirect URLs. These settings are not exposed by the connected SQL tool.
5. Rotate the previously exposed Turnstile secret in the Cloudflare Dashboard and update Supabase Auth's secret. Cloudflare documents a two-hour overlap for old/new secrets after rotation; complete the swap within that window. Never copy the secret into GitHub or chat. Then test CAPTCHA on login, signup, OTP resend and password reset.
6. Review narrowly scoped Auth logs for the test account and redact email/token data before saving QA evidence.

Useful official guidance: [Cloudflare Turnstile secret rotation](https://developers.cloudflare.com/turnstile/troubleshooting/rotate-secret-key/) and [Supabase Auth CAPTCHA setup](https://supabase.com/docs/guides/auth/auth-captcha).

**Final: Work #3 is partially complete, not fully complete, until the live email/reset tests and CAPTCHA rotation have been verified.**
