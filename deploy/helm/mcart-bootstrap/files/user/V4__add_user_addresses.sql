-- User delivery addresses (multi-address + default)
CREATE TABLE IF NOT EXISTS user_addresses (
    address_id   uuid PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES user_profile (user_id) ON DELETE CASCADE,

    full_name    text NOT NULL,
    phone        text NOT NULL,
    line1        text NOT NULL,
    line2        text NULL,
    city         text NOT NULL,
    state        text NOT NULL,
    pincode      text NOT NULL,
    country      text NOT NULL,

    is_default   boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_addresses_user_id ON user_addresses (user_id);
CREATE INDEX IF NOT EXISTS idx_user_addresses_user_default ON user_addresses (user_id, is_default);

