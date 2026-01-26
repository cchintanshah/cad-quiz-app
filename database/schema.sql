-- =============================================
-- SN Quiz App - Supabase Database Schema
-- =============================================
-- Run this in Supabase SQL Editor to set up your database

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- 1. LICENSE KEYS TABLE
-- =============================================
CREATE TABLE license_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_key TEXT UNIQUE NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    max_devices INTEGER DEFAULT 3,
    notes TEXT,
    created_by TEXT DEFAULT 'admin'
);

-- Index for faster license key lookups
CREATE INDEX idx_license_keys_key ON license_keys(license_key);
CREATE INDEX idx_license_keys_active ON license_keys(is_active);

-- =============================================
-- 2. USER PROGRESS TABLE
-- =============================================
CREATE TABLE user_progress (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_key TEXT NOT NULL REFERENCES license_keys(license_key) ON DELETE CASCADE,
    section_id TEXT NOT NULL,
    score INTEGER DEFAULT 0,
    total_questions INTEGER DEFAULT 0,
    percentage INTEGER DEFAULT 0,
    attempts INTEGER DEFAULT 1,
    best_score INTEGER DEFAULT 0,
    last_attempt_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(license_key, section_id)
);

-- Index for faster progress lookups
CREATE INDEX idx_user_progress_license ON user_progress(license_key);

-- =============================================
-- 3. QUIZ SESSIONS TABLE (For Resume Feature)
-- =============================================
CREATE TABLE quiz_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_key TEXT NOT NULL REFERENCES license_keys(license_key) ON DELETE CASCADE,
    section_id TEXT NOT NULL,
    current_question_index INTEGER DEFAULT 0,
    score INTEGER DEFAULT 0,
    question_ids JSONB NOT NULL, -- Array of question IDs in order
    answered_questions JSONB DEFAULT '[]'::jsonb, -- Array of answered question IDs
    time_remaining INTEGER,
    is_study_mode BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(license_key, section_id)
);

-- Index for session lookups
CREATE INDEX idx_quiz_sessions_license ON quiz_sessions(license_key);

-- =============================================
-- 4. BOOKMARKS TABLE
-- =============================================
CREATE TABLE bookmarks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_key TEXT NOT NULL REFERENCES license_keys(license_key) ON DELETE CASCADE,
    question_id INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(license_key, question_id)
);

-- Index for bookmark lookups
CREATE INDEX idx_bookmarks_license ON bookmarks(license_key);

-- =============================================
-- 5. WRONG ANSWERS TABLE
-- =============================================
CREATE TABLE wrong_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_key TEXT NOT NULL REFERENCES license_keys(license_key) ON DELETE CASCADE,
    question_id INTEGER NOT NULL,
    wrong_count INTEGER DEFAULT 1,
    last_wrong_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(license_key, question_id)
);

-- Index for wrong answers lookups
CREATE INDEX idx_wrong_answers_license ON wrong_answers(license_key);

-- =============================================
-- 6. ADMIN SETTINGS TABLE
-- =============================================
CREATE TABLE admin_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key TEXT UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default admin password (change this!)
INSERT INTO admin_settings (setting_key, setting_value) 
VALUES ('admin_password', 'admin123')
ON CONFLICT (setting_key) DO NOTHING;

-- =============================================
-- 7. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================

-- Enable RLS on all tables
ALTER TABLE license_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE wrong_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_settings ENABLE ROW LEVEL SECURITY;

-- Policy: Allow anonymous read access to validate license keys
CREATE POLICY "Allow license key validation" ON license_keys
    FOR SELECT USING (true);

-- Policy: Allow anonymous insert/update/delete for user data
-- (In production, you'd want more restrictive policies)
CREATE POLICY "Allow all operations on user_progress" ON user_progress
    FOR ALL USING (true);

CREATE POLICY "Allow all operations on quiz_sessions" ON quiz_sessions
    FOR ALL USING (true);

CREATE POLICY "Allow all operations on bookmarks" ON bookmarks
    FOR ALL USING (true);

CREATE POLICY "Allow all operations on wrong_answers" ON wrong_answers
    FOR ALL USING (true);

CREATE POLICY "Allow read admin settings" ON admin_settings
    FOR SELECT USING (true);

CREATE POLICY "Allow update admin settings" ON admin_settings
    FOR UPDATE USING (true);

-- =============================================
-- 8. HELPER FUNCTIONS
-- =============================================

-- Function to validate license key
CREATE OR REPLACE FUNCTION validate_license_key(key TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM license_keys 
        WHERE license_key = key 
        AND is_active = true 
        AND (expires_at IS NULL OR expires_at > NOW())
    );
END;
$$ LANGUAGE plpgsql;

-- Function to get or create user progress
CREATE OR REPLACE FUNCTION upsert_user_progress(
    p_license_key TEXT,
    p_section_id TEXT,
    p_score INTEGER,
    p_total_questions INTEGER,
    p_percentage INTEGER
)
RETURNS void AS $$
BEGIN
    INSERT INTO user_progress (license_key, section_id, score, total_questions, percentage, best_score)
    VALUES (p_license_key, p_section_id, p_score, p_total_questions, p_percentage, p_score)
    ON CONFLICT (license_key, section_id) 
    DO UPDATE SET 
        score = EXCLUDED.score,
        total_questions = EXCLUDED.total_questions,
        percentage = EXCLUDED.percentage,
        attempts = user_progress.attempts + 1,
        best_score = GREATEST(user_progress.best_score, EXCLUDED.score),
        last_attempt_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- 9. INSERT DEFAULT LICENSE KEYS
-- =============================================
INSERT INTO license_keys (license_key, notes) VALUES 
    ('SNQUIZ-2024-DEMO', 'Demo key for testing'),
    ('SNQUIZ-FREE-TRIAL', 'Free trial key')
ON CONFLICT (license_key) DO NOTHING;

-- =============================================
-- SETUP COMPLETE!
-- =============================================
-- Your database is now ready to use.
-- 
-- Next steps:
-- 1. Go to Settings > API in Supabase dashboard
-- 2. Copy your Project URL and anon/public key
-- 3. Update these values in your index.html
-- =============================================