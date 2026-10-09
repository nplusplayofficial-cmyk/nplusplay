N+ PLAY core compatibility note

This release pack intentionally does not replace core/nplus-auth.js, core/nplus-wallet-bridge.js, or core/nplus-config.js. The existing project has an email-OTP signup flow and a tested bridge already used by the games. Preserve those existing files; replacing them with a generic baseline could remove OTP methods or break login/session behavior.

The new activity/admin pages call the existing public API: NPlusAuth.current(), NPlusAuth.requireAuth(), NPlusWallet.getBalance(), NPlusWallet.transactions(), and the existing Supabase client at NPlusAuth.client.
