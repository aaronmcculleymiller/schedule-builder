-- ============================================================================
-- Sharing Feature - Additional SQL for Schedule Builder
-- ============================================================================
-- Run this in the Supabase SQL Editor AFTER the initial schema is in place.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. RPC: Invite a member by email
-- --------------------------------------------------------------------------
-- Since the client can't query auth.users directly, we use a server-side
-- function to look up a user by email and add them as a schedule member.
-- Only admins of the schedule can invite.
CREATE OR REPLACE FUNCTION invite_member_by_email(
  p_schedule_id uuid,
  p_email text,
  p_role text DEFAULT 'editor'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_user_id uuid;
  v_caller_role text;
BEGIN
  -- Check caller is admin of this schedule
  SELECT role INTO v_caller_role
  FROM schedule_members
  WHERE schedule_id = p_schedule_id AND user_id = auth.uid();

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can invite members');
  END IF;

  -- Validate role
  IF p_role NOT IN ('admin', 'editor', 'viewer') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid role. Must be admin, editor, or viewer');
  END IF;

  -- Look up the user by email in auth.users
  SELECT id INTO v_target_user_id
  FROM auth.users
  WHERE email = lower(trim(p_email));

  IF v_target_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No user found with that email. They need to sign in at least once first.');
  END IF;

  -- Check if already a member
  IF EXISTS (SELECT 1 FROM schedule_members WHERE schedule_id = p_schedule_id AND user_id = v_target_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'User is already a member of this schedule');
  END IF;

  -- Add the member
  INSERT INTO schedule_members (schedule_id, user_id, role)
  VALUES (p_schedule_id, v_target_user_id, p_role);

  RETURN jsonb_build_object('success', true, 'user_id', v_target_user_id);
END;
$$;

-- --------------------------------------------------------------------------
-- 2. RPC: Get schedule members (with emails)
-- --------------------------------------------------------------------------
-- Returns all members of a schedule with their email and display name.
-- Only members of the schedule can see the member list.
CREATE OR REPLACE FUNCTION get_schedule_members(p_schedule_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Check caller is a member
  IF NOT EXISTS (
    SELECT 1 FROM schedule_members
    WHERE schedule_id = p_schedule_id AND user_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not a member of this schedule');
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id', sm.user_id,
      'role', sm.role,
      'email', u.email,
      'display_name', COALESCE(u.raw_user_meta_data->>'full_name', u.email),
      'is_you', (sm.user_id = auth.uid())
    ) ORDER BY
      CASE sm.role WHEN 'admin' THEN 0 WHEN 'editor' THEN 1 ELSE 2 END,
      u.email
  )
  INTO v_result
  FROM schedule_members sm
  JOIN auth.users u ON u.id = sm.user_id
  WHERE sm.schedule_id = p_schedule_id;

  RETURN jsonb_build_object('success', true, 'members', COALESCE(v_result, '[]'::jsonb));
END;
$$;

-- --------------------------------------------------------------------------
-- 3. RPC: Remove a member from a schedule
-- --------------------------------------------------------------------------
-- Only admins can remove members. Admins can't remove themselves if they're
-- the last admin (to prevent orphaned schedules).
CREATE OR REPLACE FUNCTION remove_schedule_member(
  p_schedule_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role text;
  v_target_role text;
  v_admin_count int;
BEGIN
  -- Check caller is admin
  SELECT role INTO v_caller_role
  FROM schedule_members
  WHERE schedule_id = p_schedule_id AND user_id = auth.uid();

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can remove members');
  END IF;

  -- Check target exists
  SELECT role INTO v_target_role
  FROM schedule_members
  WHERE schedule_id = p_schedule_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'User is not a member');
  END IF;

  -- If removing an admin, ensure at least one admin remains
  IF v_target_role = 'admin' THEN
    SELECT count(*) INTO v_admin_count
    FROM schedule_members
    WHERE schedule_id = p_schedule_id AND role = 'admin';

    IF v_admin_count <= 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Cannot remove the last admin');
    END IF;
  END IF;

  DELETE FROM schedule_members
  WHERE schedule_id = p_schedule_id AND user_id = p_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- --------------------------------------------------------------------------
-- 4. RPC: Update a member's role
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_member_role(
  p_schedule_id uuid,
  p_user_id uuid,
  p_new_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role text;
  v_admin_count int;
BEGIN
  -- Check caller is admin
  SELECT role INTO v_caller_role
  FROM schedule_members
  WHERE schedule_id = p_schedule_id AND user_id = auth.uid();

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can change roles');
  END IF;

  -- Validate role
  IF p_new_role NOT IN ('admin', 'editor', 'viewer') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid role');
  END IF;

  -- If demoting an admin, ensure at least one admin remains
  IF p_new_role != 'admin' THEN
    SELECT count(*) INTO v_admin_count
    FROM schedule_members
    WHERE schedule_id = p_schedule_id AND role = 'admin' AND user_id != p_user_id;

    IF v_admin_count < 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'Cannot demote the last admin');
    END IF;
  END IF;

  UPDATE schedule_members
  SET role = p_new_role
  WHERE schedule_id = p_schedule_id AND user_id = p_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
