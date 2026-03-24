ALTER TABLE user_profile ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX idx_user_profile_email_verified ON user_profile (email_verified);
