-- Create journal_entries table for user-facing curated view
CREATE TABLE journal_entries (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tank_id TEXT NOT NULL,
  date TEXT NOT NULL,           -- YYYY-MM-DD
  category TEXT NOT NULL,       -- 'measurements', 'actions', 'notes'
  data TEXT NOT NULL,           -- JSON (object for measurements, array for actions/notes)
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, tank_id, date, category)
);

-- Enable RLS
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;

-- Users can only see/modify their own journal entries
CREATE POLICY "Users can view own journal entries"
  ON journal_entries FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own journal entries"
  ON journal_entries FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own journal entries"
  ON journal_entries FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own journal entries"
  ON journal_entries FOR DELETE
  USING (auth.uid() = user_id);

-- Index for fast lookups by user + tank
CREATE INDEX idx_journal_entries_user_tank ON journal_entries(user_id, tank_id);
