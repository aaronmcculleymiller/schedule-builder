-- ============================================================================
-- Fix: Allow editors to delete child rows (not just admins)
-- ============================================================================
-- The save strategy deletes all children then re-inserts. The original RLS
-- delete policies only allowed admins, so editors got "duplicate key" errors
-- because their deletes silently returned 0 rows.
-- Run this in the Supabase SQL Editor.
-- ============================================================================

DROP POLICY event_types_delete ON event_types;
CREATE POLICY event_types_delete ON event_types FOR DELETE USING (
  is_schedule_editor(schedule_id, auth.uid())
);

DROP POLICY days_delete ON days;
CREATE POLICY days_delete ON days FOR DELETE USING (
  is_schedule_editor(schedule_id, auth.uid())
);

DROP POLICY locations_delete ON locations;
CREATE POLICY locations_delete ON locations FOR DELETE USING (
  is_schedule_editor(schedule_id, auth.uid())
);

DROP POLICY day_locations_delete ON day_locations;
CREATE POLICY day_locations_delete ON day_locations FOR DELETE USING (
  is_schedule_editor(
    (SELECT schedule_id FROM days WHERE id = day_locations.day_id),
    auth.uid()
  )
);
