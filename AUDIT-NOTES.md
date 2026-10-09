# Audit notes

Observed from the supplied current files:
- Inline JavaScript syntax checks pass for the staged HTML pages.
- Shared wallet pages invoke the existing NPlusWallet bridge / `nplus_wallet_change` RPC.
- The current repo already has an email-OTP-capable `core/nplus-auth.js`; this package intentionally preserves it rather than replacing it.
- The browser cannot run a real Supabase integration test in this environment.
- The `nplus_wallet_change` function body was not supplied as SQL in this runtime, so its actual server-side validation cannot be verified here. Treat positive client-side win credits as an unresolved security blocker until the legacy function is inspected and replaced by server-authoritative settlement RPCs.
