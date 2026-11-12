-- ============================================================================
-- Conference Schedule Builder - Supabase Schema
-- ============================================================================
-- Run this entire script in the Supabase SQL Editor.
-- Assumes Supabase Auth is enabled with Google OAuth provider configured.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 0. Extensions
-- --------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- for gen_random_uuid()

-- --------------------------------------------------------------------------
-- 1. TABLES
-- --------------------------------------------------------------------------

-- Top-level schedule document
CREATE TABLE schedules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL DEFAULT 'Untitled Schedule',
  created_by  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Role-based membership (admin / editor / viewer)
CREATE TABLE schedule_members (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('admin', 'editor', 'viewer')) DEFAULT 'viewer',
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (schedule_id, user_id)
);

-- Per-schedule custom event types with colors
CREATE TABLE event_types (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  key         text NOT NULL,            -- e.g. 'event-type-1'
  label       text NOT NULL,            -- e.g. 'Keynote'
  color       text NOT NULL DEFAULT '#6b7280',  -- hex color
  sort_order  int  NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (schedule_id, key)
);

-- Ordered days within a schedule
CREATE TABLE days (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id   uuid NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  label         text NOT NULL,          -- e.g. 'Day 1', 'Monday June 5'
  sort_order    int  NOT NULL DEFAULT 0,
  start_hour    int  NOT NULL DEFAULT 7  CHECK (start_hour >= 0 AND start_hour <= 23),
  end_hour      int  NOT NULL DEFAULT 22 CHECK (end_hour   >= 1 AND end_hour   <= 24),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT valid_hour_range CHECK (end_hour > start_hour)
);

-- Locations (rooms / venues) global to a schedule
CREATE TABLE locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id uuid NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  name        text NOT NULL,
  notes       text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Which locations appear on which day, with display ordering
CREATE TABLE day_locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day_id      uuid NOT NULL REFERENCES days(id)      ON DELETE CASCADE,
  location_id uuid NOT NULL REFERENCES locations(id)  ON DELETE CASCADE,
  sort_order  int  NOT NULL DEFAULT 0,
  UNIQUE (day_id, location_id)
);

-- Session / event blocks
CREATE TABLE events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day_id        uuid NOT NULL REFERENCES days(id)         ON DELETE CASCADE,
  event_type_id uuid          REFERENCES event_types(id)  ON DELETE SET NULL,
  title         text NOT NULL DEFAULT '',
  start_time    time NOT NULL,          -- e.g. '09:00'
  end_time      time NOT NULL,          -- e.g. '10:00'
  all_locations boolean NOT NULL DEFAULT false,  -- spans every room on that day
  notes         text NOT NULL DEFAULT '',         -- volunteer / misc notes
  description   text NOT NULL DEFAULT '',         -- longer description (not shown on grid)
  show_time     boolean NOT NULL DEFAULT true,    -- whether to display time on the grid
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Many-to-many: which locations an event occupies (ignored when all_locations = true)
CREATE TABLE event_locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    uuid NOT NULL REFERENCES events(id)    ON DELETE CASCADE,
  location_id uuid NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  UNIQUE (event_id, location_id)
);

-- --------------------------------------------------------------------------
-- 2. INDEXES (beyond PKs and unique constraints)
-- --------------------------------------------------------------------------
CREATE INDEX idx_schedule_members_user     ON schedule_members(user_id);
CREATE INDEX idx_schedule_members_schedule ON schedule_members(schedule_id);
CREATE INDEX idx_days_schedule             ON days(schedule_id);
CREATE INDEX idx_locations_schedule        ON locations(schedule_id);
CREATE INDEX idx_events_day               ON events(day_id);
CREATE INDEX idx_event_types_schedule      ON event_types(schedule_id);
CREATE INDEX idx_event_locations_event     ON event_locations(event_id);
CREATE INDEX idx_event_locations_location  ON event_locations(location_id);

-- --------------------------------------------------------------------------
-- 3. UPDATED_AT TRIGGER
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_schedules_updated_at
  BEFORE UPDATE ON schedules
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_events_updated_at
  BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- --------------------------------------------------------------------------
-- 4. HELPER FUNCTION: check a user's role for a given schedule
-- --------------------------------------------------------------------------
-- Returns the role text ('admin', 'editor', 'viewer') or NULL if not a member.

CREATE OR REPLACE FUNCTION get_schedule_role(p_schedule_id uuid, p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT role FROM schedule_members
  WHERE schedule_id = p_schedule_id AND user_id = p_user_id
  LIMIT 1;
$$;

-- Convenience: is viewer or higher (any member)?
CREATE OR REPLACE FUNCTION is_schedule_member(p_schedule_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM schedule_members
    WHERE schedule_id = p_schedule_id AND user_id = p_user_id
  );
$$;

-- Convenience: is editor or admin?
CREATE OR REPLACE FUNCTION is_schedule_editor(p_schedule_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM schedule_members
    WHERE schedule_id = p_schedule_id AND user_id = p_user_id
      AND role IN ('editor', 'admin')
  );
$$;

-- Convenience: is admin?
CREATE OR REPLACE FUNCTION is_schedule_admin(p_schedule_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM schedule_members
    WHERE schedule_id = p_schedule_id AND user_id = p_user_id
      AND role = 'admin'
  );
$$;

-- --------------------------------------------------------------------------
-- 5. ENABLE RLS ON ALL TABLES
-- --------------------------------------------------------------------------
ALTER TABLE schedules        ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_types      ENABLE ROW LEVEL SECURITY;
ALTER TABLE days             ENABLE ROW LEVEL SECURITY;
ALTER TABLE locations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE day_locations    ENABLE ROW LEVEL SECURITY;
ALTER TABLE events           ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_locations  ENABLE ROW LEVEL SECURITY;

-- --------------------------------------------------------------------------
-- 6. RLS POLICIES
-- --------------------------------------------------------------------------

-- ======================== schedules ========================

-- Any member can read the schedule
CREATE POLICY schedules_select ON schedules FOR SELECT USING (
  is_schedule_member(id, auth.uid())
);

-- Any authenticated user can create a schedule (they become admin via trigger)
CREATE POLICY schedules_insert ON schedules FOR INSERT WITH CHECK (
  auth.uid() = created_by
);

-- Only admins can update schedule metadata (name, etc.)
CREATE POLICY schedules_update ON schedules FOR UPDATE USING (
  is_schedule_admin(id, auth.uid())
);

-- Only admins can delete the schedule
CREATE POLICY schedules_delete ON schedules FOR DELETE USING (
  is_schedule_admin(id, auth.uid())
);

-- ======================== schedule_members ========================

-- Members can see who else is in their schedule
CREATE POLICY members_select ON schedule_members FOR SELECT USING (
  is_schedule_member(schedule_id, auth.uid())
);

-- Only admins can add members
CREATE POLICY members_insert ON schedule_members FOR INSERT WITH CHECK (
  is_schedule_admin(schedule_id, auth.uid())
);

-- Only admins can change roles
CREATE POLICY members_update ON schedule_members FOR UPDATE USING (
  is_schedule_admin(schedule_id, auth.uid())
);

-- Only admins can remove members
CREATE POLICY members_delete ON schedule_members FOR DELETE USING (
  is_schedule_admin(schedule_id, auth.uid())
);

-- ======================== event_types ========================

CREATE POLICY event_types_select ON event_types FOR SELECT USING (
  is_schedule_member(schedule_id, auth.uid())
);

-- Editors+ can manage event types
CREATE POLICY event_types_insert ON event_types FOR INSERT WITH CHECK (
  is_schedule_editor(schedule_id, auth.uid())
);

CREATE POLICY event_types_update ON event_types FOR UPDATE USING (
  is_schedule_editor(schedule_id, auth.uid())
);

CREATE POLICY event_types_delete ON event_types FOR DELETE USING (
  is_schedule_admin(schedule_id, auth.uid())
);

-- ======================== days ========================

CREATE POLICY days_select ON days FOR SELECT USING (
  is_schedule_member(schedule_id, auth.uid())
);

CREATE POLICY days_insert ON days FOR INSERT WITH CHECK (
  is_schedule_editor(schedule_id, auth.uid())
);

CREATE POLICY days_update ON days FOR UPDATE USING (
  is_schedule_editor(schedule_id, auth.uid())
);

CREATE POLICY days_delete ON days FOR DELETE USING (
  is_schedule_admin(schedule_id, auth.uid())
);

-- ======================== locations ========================

CREATE POLICY locations_select ON locations FOR SELECT USING (
  is_schedule_member(schedule_id, auth.uid())
);

CREATE POLICY locations_insert ON locations FOR INSERT WITH CHECK (
  is_schedule_editor(schedule_id, auth.uid())
);

CREATE POLICY locations_update ON locations FOR UPDATE USING (
  is_schedule_editor(schedule_id, auth.uid())
);

CREATE POLICY locations_delete ON locations FOR DELETE USING (
  is_schedule_admin(schedule_id, auth.uid())
);

-- ======================== day_locations ========================
-- Junction table: derive schedule from day_id -> days.schedule_id

CREATE POLICY day_locations_select ON day_locations FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_member(d.schedule_id, auth.uid())
  )
);

CREATE POLICY day_locations_insert ON day_locations FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

CREATE POLICY day_locations_update ON day_locations FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

CREATE POLICY day_locations_delete ON day_locations FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_admin(d.schedule_id, auth.uid())
  )
);

-- ======================== events ========================
-- Derive schedule from day_id -> days.schedule_id

CREATE POLICY events_select ON events FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_member(d.schedule_id, auth.uid())
  )
);

CREATE POLICY events_insert ON events FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

CREATE POLICY events_update ON events FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

CREATE POLICY events_delete ON events FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM days d
    WHERE d.id = day_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

-- ======================== event_locations ========================
-- Derive schedule from event_id -> events.day_id -> days.schedule_id

CREATE POLICY event_locations_select ON event_locations FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM events e
    JOIN days d ON d.id = e.day_id
    WHERE e.id = event_id AND is_schedule_member(d.schedule_id, auth.uid())
  )
);

CREATE POLICY event_locations_insert ON event_locations FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM events e
    JOIN days d ON d.id = e.day_id
    WHERE e.id = event_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

CREATE POLICY event_locations_update ON event_locations FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM events e
    JOIN days d ON d.id = e.day_id
    WHERE e.id = event_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

CREATE POLICY event_locations_delete ON event_locations FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM events e
    JOIN days d ON d.id = e.day_id
    WHERE e.id = event_id AND is_schedule_editor(d.schedule_id, auth.uid())
  )
);

-- --------------------------------------------------------------------------
-- 7. AUTO-ADD CREATOR AS ADMIN
-- --------------------------------------------------------------------------
-- When a schedule is created, automatically insert the creator as an admin member.

CREATE OR REPLACE FUNCTION auto_add_schedule_admin()
RETURNS trigger AS $$
BEGIN
  INSERT INTO schedule_members (schedule_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'admin');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_auto_add_schedule_admin
  AFTER INSERT ON schedules
  FOR EACH ROW EXECUTE FUNCTION auto_add_schedule_admin();

-- --------------------------------------------------------------------------
-- 8. REALTIME
-- --------------------------------------------------------------------------
-- Enable Supabase Realtime on the tables that change frequently.
-- Users subscribe to changes filtered by schedule membership.

ALTER PUBLICATION supabase_realtime ADD TABLE events;
ALTER PUBLICATION supabase_realtime ADD TABLE event_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE days;
ALTER PUBLICATION supabase_realtime ADD TABLE day_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE locations;
ALTER PUBLICATION supabase_realtime ADD TABLE event_types;
ALTER PUBLICATION supabase_realtime ADD TABLE schedule_members;

-- --------------------------------------------------------------------------
-- 9. SEED DEFAULT EVENT TYPES (optional helper function)
-- --------------------------------------------------------------------------
-- Call this after creating a schedule to populate the 6 built-in types.

CREATE OR REPLACE FUNCTION seed_default_event_types(p_schedule_id uuid)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO event_types (schedule_id, key, label, color, sort_order) VALUES
    (p_schedule_id, 'event-type-1', 'Event Type 1', '#ff57f9', 1),
    (p_schedule_id, 'event-type-2', 'Event Type 2', '#00b3ff', 2),
    (p_schedule_id, 'event-type-3', 'Event Type 3', '#00d68f', 3),
    (p_schedule_id, 'event-type-4', 'Event Type 4', '#ffc107', 4),
    (p_schedule_id, 'event-type-5', 'Event Type 5', '#ff6b6b', 5),
    (p_schedule_id, 'event-type-6', 'Event Type 6', '#a78bfa', 6);
$$;

-- ============================================================================
-- DONE. Summary of tables:
--
--   schedules          - top-level schedule document
--   schedule_members   - RBAC: admin / editor / viewer per user per schedule
--   event_types        - custom session types with colors (per schedule)
--   days               - ordered days with start/end hours
--   locations          - rooms/venues (per schedule)
--   day_locations      - which locations appear on which day, with ordering
--   events             - session time blocks
--   event_locations    - many-to-many: events <-> locations
--
-- RLS enforces:
--   viewer  -> SELECT only
--   editor  -> SELECT, INSERT, UPDATE (+ DELETE on events/event_locations)
--   admin   -> full CRUD on everything, including member management
--
-- The creator of a schedule is automatically granted the admin role.
-- Supabase Realtime is enabled on all mutable content tables.
-- ============================================================================
