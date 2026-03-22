-- Profile row for bootstrap admin (same user_id as auth DB). Idempotent.
INSERT INTO "user" (user_id, email, first_name, last_name, created_at, updated_at)
SELECT
    'f0000000-0000-4000-8000-000000000002'::uuid,
    'bootstrap.admin@mcart.internal',
    'Bootstrap',
    'Admin',
    NOW(),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM "user" WHERE user_id = 'f0000000-0000-4000-8000-000000000002'::uuid
);
