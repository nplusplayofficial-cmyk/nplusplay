N+ PLAY — READ-ONLY AUDIT CODE PACK

IMPORTANT:
- This is a diagnostic SQL script only. It does not modify the database.
- Do NOT run NPLUS_PLAY_PREMIUM_FOUNDATION.sql yet.

HOW TO USE:
1. Open Supabase Dashboard for the N+ PLAY project.
2. Open SQL Editor -> New query.
3. Copy the full contents of sql/00-READ-ONLY-SUPABASE-AUDIT.sql into the editor.
4. Run it.
5. It returns several result sets about tables, columns, RLS policies, grants and existing RPC definitions.
6. Send screenshots or copy the output for sections 1, 2, 3 and especially 5. Hide any secret values if any appear.

WHY:
The Premium Release ZIP intentionally preserves the working core auth/wallet files. Replacing those blindly may break OTP login or wallet/game integration. Current RPC source and policies must be reviewed before writing secure server-side settlement code or running the migration.

This audit pack is additional. Do not upload it over index.html or other site files. The SQL file is run in Supabase SQL Editor, not in GitHub.
