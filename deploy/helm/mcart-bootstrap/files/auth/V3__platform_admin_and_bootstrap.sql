-- Platform admin flag (JWT includes scope product.admin when true).
ALTER TABLE auth_user
    ADD COLUMN IF NOT EXISTS platform_admin BOOLEAN NOT NULL DEFAULT FALSE;

-- Bootstrap admin (idempotent). Identifier / email: bootstrap.admin@mcart.internal
-- Password: ChangeMeAfterFirstDeploy! — change after first deploy.
-- Regenerate password hash: ./gradlew generateBootstrapPasswordHash -PbootstrapPassword='...' (auth module)
INSERT INTO auth_identity (
    auth_identity_id,
    user_id,
    provider_type,
    provider_user_id,
    identifier,
    password_hash,
    email,
    email_verified,
    email_verified_at,
    created_at,
    last_login_at
)
SELECT
    'f0000000-0000-4000-8000-000000000001'::uuid,
    'f0000000-0000-4000-8000-000000000002'::uuid,
    'PASSWORD',
    NULL,
    'bootstrap.admin@mcart.internal',
    '$argon2id$v=19$m=65536,t=3,p=1$rvbTxi43tYCG+YqGkwHEsw$fiMoJ0fHvZylfLfchlcaeXpNqqIB9Ht54UIfct8iaG8',
    'bootstrap.admin@mcart.internal',
    TRUE,
    NOW(),
    NOW(),
    NULL
WHERE NOT EXISTS (
    SELECT 1 FROM auth_identity
    WHERE provider_type = 'PASSWORD' AND identifier = 'bootstrap.admin@mcart.internal'
);

INSERT INTO auth_user (
    auth_identity_id,
    user_id,
    status,
    locked_until,
    created_at,
    updated_at,
    platform_admin
)
SELECT
    'f0000000-0000-4000-8000-000000000001'::uuid,
    'f0000000-0000-4000-8000-000000000002'::uuid,
    'ACTIVE',
    NULL,
    NOW(),
    NOW(),
    TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM auth_user WHERE auth_identity_id = 'f0000000-0000-4000-8000-000000000001'::uuid
);
