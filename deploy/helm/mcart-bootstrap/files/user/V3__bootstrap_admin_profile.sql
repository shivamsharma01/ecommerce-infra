-- Profile row for bootstrap admin (same user_id as auth DB). Idempotent.
INSERT INTO user_profile (user_id, email, first_name, last_name, created_at, updated_at, email_verified)
SELECT
    'f0000000-0000-4000-8000-000000000002'::uuid,
    'bootstrap.admin@mcart.internal',
    'Bootstrap',
    'Admin',
    NOW(),
    NOW(),
    't'
WHERE NOT EXISTS (
    SELECT 1 FROM user_profile WHERE user_id = 'f0000000-0000-4000-8000-000000000002'::uuid
);
