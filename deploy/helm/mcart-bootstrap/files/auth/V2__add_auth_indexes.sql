-- Login by email / username
CREATE INDEX idx_auth_identity_identifier
    ON auth_identity (identifier);

-- Social login lookup
CREATE INDEX idx_auth_identity_provider_user
    ON auth_identity (provider_type, provider_user_id);

-- Fetch identities for a user
CREATE INDEX idx_auth_identity_user
    ON auth_identity (user_id);



-- Used for account checks
CREATE INDEX idx_auth_user_status
    ON auth_user (status);

CREATE INDEX idx_auth_user_locked_until
    ON auth_user (locked_until);



-- Cleanup job
CREATE INDEX idx_email_verification_expires
    ON email_verification (expires_at);

-- Verification lookup
CREATE INDEX idx_email_verification_identity
    ON email_verification (auth_identity_id);



-- Polling unsent events
CREATE INDEX idx_outbox_event_status
    ON outbox_event (status, created_at);

-- Retry scheduling
CREATE INDEX idx_outbox_event_retry
    ON outbox_event (retry_count, last_attempt_at);

-- Aggregate based replay / debugging
CREATE INDEX idx_outbox_event_aggregate
    ON outbox_event (aggregate_type, aggregate_id);