# Prompt for Airtable Omni: Conference Program Builder

Use this as a starting prompt in Omni, then iterate from there. Because Omni works best when you build incrementally, I've broken this into a sequence of prompts rather than one giant request.

---

## Prompt 1: Create the Data Model

> Build me a conference program scheduling app. I need to plan sessions across multiple rooms over multiple days for a museum conference (MCN).
>
> Create these tables:
>
> **Sessions** — each record is one scheduled session, with these fields:
> - Session Title (single line text, primary field)
> - Start Time (date and time)
> - End Time (date and time)
> - Session Type (linked to Session Types table)
> - Room (linked to Rooms table)
> - Volunteer Name (single line text, optional)
> - Day (formula that extracts just the date from Start Time, so I can group/filter by day)
> - All Rooms (checkbox — if checked, this session spans every room, like lunch breaks or passing time)
> - Notes (long text, optional)
>
> **Rooms** — each record is a room or event space:
> - Room Name (single line text, primary field)
> - Capacity (number, optional)
> - Active Days (linked to Days table — which days this room is used)
>
> **Session Types** — color-coded categories:
> - Type Name (single line text, primary field)
> - Color (single select with these options: Admin Time, Social/Networking, Passing Time, Session, Open Space, Sponsor)
>
> **Days** — one record per conference day:
> - Day Name (single line text, primary field — e.g., "Oct 21", "Day 1", "Monday")
> - Date (date field)
>
> Pre-populate Session Types with: Admin Time, Social/Networking, Passing Time, Session, Open Space, Sponsor.

---

## Prompt 2: Create the Timeline View

> Now create a Timeline view on the Sessions table. Configure it so:
> - The timeline uses Start Time and End Time as the date fields
> - Group the records (swimlanes) by Room
> - Set the record width to "Precise" so I can drag and drop sessions to reschedule them
> - Color the records by Session Type
> - Filter to show only one day at a time (I'll switch the filter to see different days)
>
> This is the main scheduling workspace — I need to be able to drag sessions between rooms and time slots to rearrange the program.

---

## Prompt 3: Create a Day-Switching Interface

> Create an interface for the app with a dashboard page. Add:
> - A filter or dropdown at the top that lets me switch between days
> - An embedded timeline element showing sessions for the selected day, grouped by room
> - A button or form to quickly add a new session with all the fields pre-populated for the current day

---

## Prompt 4: Create a Session Entry Form

> Create a form view or interface page for adding sessions. It should include:
> - Session Title
> - Start Time and End Time (defaulting to today's date)
> - Session Type (dropdown from the linked table)
> - Room (dropdown from the linked table, or an "All Rooms" checkbox)
> - Volunteer Name
>
> When "All Rooms" is checked, the Room field should be optional. I'll need an automation later to handle "All Rooms" sessions.

---

## Prompt 5: Room Management

> Add an interface page for managing rooms. I want to:
> - See all rooms in a list with their capacity
> - Add new rooms
> - Edit room names and capacity
> - Assign which days each room is active (so I can have different rooms on different conference days)

---

## Prompt 6: Add Sample Data

> Pre-populate the app with sample data for one conference day ("Oct 21"):
>
> Rooms: Room 1, Room 2, Room 3, Room 4, Room 6, Room 7
>
> Sessions:
> - 8:00–9:00 AM: "Set-up Time" (Admin Time, All Rooms)
> - 9:00–9:15 AM: "Passing Time" (Passing Time, All Rooms)
> - 9:15–10:00 AM: "Opening Remarks with Featured Speakers" (Session, Room 1)
> - 10:00–10:15 AM: "Passing Time" (Passing Time, All Rooms)
> - 10:15–11:30 AM: Multiple concurrent sessions across all rooms (mix of Session, Sponsor, and Social/Networking types)
> - 11:30–11:45 AM: "Passing Time" (Passing Time, All Rooms)
> - 11:45 AM–12:00 PM: Sessions across rooms (with some TBD volunteer names)
> - 12:00–1:00 PM: "Lunch Break / Networking Time" (Social/Networking, All Rooms)

---

## What to Expect: Differences from the Custom HTML Version

Airtable's approach is fundamentally different from the standalone HTML app. Here's what you gain and what you trade off:

**What works well in Airtable:**
- The Timeline view with swimlanes grouped by Room is a natural fit for this kind of scheduling — you get drag-and-drop rescheduling between rooms out of the box
- Color coding by session type works natively via single-select or linked record coloring
- Multiple people can collaborate on the schedule simultaneously
- Filtering by day gives you the equivalent of tabs
- You get forms, search, sorting, and reporting for free

**What won't translate directly:**
- "All Rooms" sessions that visually span every column don't have a native equivalent. You'd either create a separate record for each room (via automation) or accept that they appear in just one swimlane. An automation prompt like: *"When the All Rooms checkbox is checked on a session, automatically create linked copies of that session in every active room for that day"* can help.
- 5-minute snapping precision depends on the timeline zoom level. Airtable's timeline may not snap to exactly 5-minute increments the way the custom app does.
- The visual density of the custom app (20px rows, every 5 minutes labeled) won't be replicated — Airtable's timeline has its own zoom levels and visual style.
- Session Types as a linked table is more structured than the custom app's simple key/color map, but it also means you can't just click a color swatch to change a type's color. You'd update the single-select options instead.

**Tips for iterating with Omni:**
- Start with the data model and timeline view, then refine the interface incrementally.
- If something doesn't look right, describe what you see and what you want changed — Omni works best with specific, iterative feedback.
- You can always manually adjust what Omni creates using Airtable's standard interface designer and field configuration tools.
