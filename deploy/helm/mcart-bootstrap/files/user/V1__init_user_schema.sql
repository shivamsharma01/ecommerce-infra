CREATE TABLE user_profile (
    user_id       UUID PRIMARY KEY,
    email         TEXT NOT NULL,
    first_name    TEXT NOT NULL,
    last_name     TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_profile_email UNIQUE (email)
);

CREATE INDEX idx_user_profile_email ON user_profile (email);
