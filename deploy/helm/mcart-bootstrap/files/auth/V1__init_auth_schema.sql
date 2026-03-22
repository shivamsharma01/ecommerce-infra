CREATE TABLE auth_identity (
    auth_identity_id UUID PRIMARY KEY,
    user_id          UUID NOT NULL,

    provider_type    VARCHAR(32) NOT NULL,
    provider_user_id TEXT,
    identifier       TEXT,
    password_hash    TEXT,

    email            TEXT,
    email_verified   BOOLEAN NOT NULL DEFAULT FALSE,
    email_verified_at TIMESTAMPTZ,

    created_at       TIMESTAMPTZ NOT NULL,
    last_login_at    TIMESTAMPTZ,

    CONSTRAINT uq_provider_user
        UNIQUE (provider_type, provider_user_id),

    CONSTRAINT uq_provider_identifier
        UNIQUE (provider_type, identifier)
);


CREATE TABLE auth_user (
    auth_identity_id UUID PRIMARY KEY,
    user_id          UUID NOT NULL,

    status           VARCHAR(32) NOT NULL,
    locked_until     TIMESTAMPTZ,

    created_at       TIMESTAMPTZ NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_auth_user_identity
        FOREIGN KEY (auth_identity_id)
        REFERENCES auth_identity(auth_identity_id)
        ON DELETE CASCADE
);


CREATE TABLE email_verification (
    verification_id  UUID PRIMARY KEY,
    auth_identity_id UUID NOT NULL,

    email            TEXT NOT NULL,
    token            TEXT NOT NULL UNIQUE,

    expires_at       TIMESTAMPTZ NOT NULL,
    verified_at      TIMESTAMPTZ,

    CONSTRAINT fk_email_verification_identity
        FOREIGN KEY (auth_identity_id)
        REFERENCES auth_identity(auth_identity_id)
        ON DELETE CASCADE
);


CREATE TABLE outbox_event (
    id              UUID NOT NULL,
    aggregate_id    UUID NOT NULL,

    aggregate_type  VARCHAR(64) NOT NULL,
    user_id         UUID NOT NULL,

    event_type      VARCHAR(64) NOT NULL,
    payload         JSONB NOT NULL,

    status          VARCHAR(32) NOT NULL,
    retry_count     INTEGER NOT NULL DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL,
    last_attempt_at TIMESTAMPTZ,

    CONSTRAINT pk_outbox_event PRIMARY KEY (id, aggregate_id)
);