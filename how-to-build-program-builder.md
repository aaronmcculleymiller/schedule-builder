# How to Build a Conference Program Builder with Claude

These instructions will guide Claude (or another AI assistant) through building an interactive, drag-and-drop conference schedule planning tool as a single HTML file. The result is a browser-based app that replaces spreadsheet-based conference program planning with a visual, draggable grid.

---

## What You're Building

A single-file HTML application (no dependencies, no build tools, no server) that lets conference organizers visually arrange sessions across rooms and time slots. Users can drag session blocks to reschedule them, manage rooms and session types with color coding, and organize multi-day events across tabs. Everything runs in the browser and state can be saved/loaded as JSON.

---

## Step 1: Define the Core Layout

Ask Claude to create a single HTML file with embedded CSS and JavaScript. The layout has four main areas stacked vertically:

**Header bar** at the top with the app title and action buttons (Save JSON, Load JSON, Manage Session Types). Use a dark background (#2c3e50) with white text.

**Tab bar** below the header for switching between days/events. Each tab is a clickable button with an X to remove it, plus a "+" button to add new tabs. Tabs should be renamable by double-clicking (they don't have to be dates, they can be any text like "Day 1" or "Monday").

**Toolbar** with a "Manage Rooms" button and an "+ Add Session" button.

**Schedule grid** filling the remaining vertical space. This is the main workspace and must scroll both horizontally and vertically. It consists of a sticky time column on the left and one column per room extending to the right.

Key CSS requirements: use `display: flex` with `flex-direction: column` and `height: 100vh` on the container so the grid fills available space. The scroll container should have `overflow: auto` and `flex: 1`.

---

## Step 2: Build the Time Column

The time column should span from 7 AM to 9 PM in 5-minute increments. Define constants:

```
ROW_HEIGHT = 20px (height of each 5-minute slot)
START_HOUR = 7
END_HOUR = 21
SLOTS_PER_HOUR = 12 (60 min / 5 min)
TOTAL_SLOTS = (END_HOUR - START_HOUR) * SLOTS_PER_HOUR = 168
```

Every slot gets a text label. Use three visual tiers: hour marks get bold text and a heavier top border, 15-minute marks get medium styling, and 5-minute marks get light/subtle text. Format times as "9:00 AM", "9:15", "9:20", etc. (only hour marks get the AM/PM suffix).

The time column must be sticky (`position: sticky; left: 0; z-index: 3`) so it stays visible when scrolling horizontally. The time header cell (top-left corner) should also be sticky vertically (`position: sticky; top: 0; z-index: 4`).

---

## Step 3: Build Room Columns

Each room gets a column with a sticky header (room name, optional capacity, and an X button to remove the room from the current tab) and a body area for session blocks.

The room body should be `position: relative` with a fixed height of `TOTAL_SLOTS * ROW_HEIGHT` pixels. Use `repeating-linear-gradient` on the background to draw grid lines that match the time column's visual tiers:

- Heavy lines every 240px (1 hour = 12 slots * 20px)
- Medium lines every 60px (15 minutes = 3 slots * 20px)
- Light lines every 20px (5 minutes = 1 slot * 20px)

Room headers should be `position: sticky; top: 0; z-index: 2` so they stay visible when scrolling vertically. Allow double-clicking the room name to rename it.

---

## Step 4: Session Blocks with Absolute Positioning

Sessions are rendered as absolutely-positioned div elements inside their room's body container. Calculate position from the session's start time and height from its duration:

```
top = getSlotForTime(startTime) * ROW_HEIGHT
height = (getSlotForTime(endTime) - getSlotForTime(startTime)) * ROW_HEIGHT
```

Each session block should display: the session title (wrapping text), and optionally a volunteer name below it (with some margin between them). Both should use the same font size and weight. Background color comes from the session's type. Use a contrast function to pick black or white text based on background luminance.

**"All Rooms" sessions** (like lunch breaks or passing time) should be rendered in every room column simultaneously, spanning the full column width, with slightly reduced opacity. These are not draggable.

**Overlap handling**: When multiple sessions occupy the same time slot in the same room, lay them out side by side. Write a `calculateOverlapLayout()` function that groups overlapping sessions, assigns each a column index within the group, and sets `left` and `width` as percentages (e.g., two overlapping sessions each get 50% width).

---

## Step 5: Drag and Drop

Use the HTML5 Drag and Drop API. Only non-"all rooms" sessions should be draggable.

**Critical implementation details:**

On `dragstart`, record `dragOffsetY = e.clientY - sessionBlock.getBoundingClientRect().top`. This tracks where within the block the user grabbed it.

On `dragover` (on the room body), call `e.preventDefault()` and set `e.dataTransfer.dropEffect = 'move'`. Optionally add a visual highlight class.

On `drop`, calculate the new time slot:

```
relativeY = e.clientY - roomBody.getBoundingClientRect().top - dragOffsetY
slot = Math.round(relativeY / ROW_HEIGHT)  // Use Math.round, not Math.floor
```

**Do NOT add `scrollContainer.scrollTop`** to the calculation. `getBoundingClientRect()` already accounts for scroll position. Adding it again will double-count and break positioning.

Preserve the session's duration when moving it: calculate the span in slots, then set `endTime = startTime + span * 5 minutes`. Update the session's `roomIds` to the drop target room.

---

## Step 6: Data Model

Use a single `state` object stored in a JavaScript variable (no localStorage/sessionStorage). The structure:

```javascript
let state = {
  dates: ['Day 1'],              // Tab names (array of strings)
  currentDate: 'Day 1',          // Active tab
  allRooms: [                    // Global room registry
    { id: 1, name: 'Room 1', capacity: null },
    // ...
  ],
  tabRooms: {                    // Which rooms appear on each tab (IDs only)
    'Day 1': [1, 2, 3],
  },
  sessions: {                    // Sessions per tab
    'Day 1': [
      {
        id: 1,
        title: 'Session Title',
        startTime: '09:00',
        endTime: '10:00',
        type: 'session',         // References sessionTypes key
        volunteer: '',
        allRooms: false,         // If true, spans all rooms
        roomIds: [1]             // Which room(s) this session is in
      }
    ]
  },
  sessionTypes: {                // Color-coded categories
    'session': { label: 'Session', color: '#b6d7a8' },
    'passing-time': { label: 'Passing Time', color: '#00ffff' },
    // ...
  },
  nextSessionId: 2,
  nextRoomId: 4,
  draggingSession: null,
  dragOffsetY: 0,
  selectedSession: null
};
```

**The room model is a global registry with per-tab assignment.** `allRooms` is the master list of every room definition. `tabRooms` maps each tab name to an array of room IDs that appear on that tab. This means removing a room from a tab doesn't delete it globally, and existing rooms can be added to new tabs.

Write a helper `currentRooms()` that resolves the current tab's room IDs to full room objects:

```javascript
function currentRooms() {
  return (state.tabRooms[state.currentDate] || [])
    .map(id => state.allRooms.find(r => r.id === id))
    .filter(r => r != null);
}
```

---

## Step 7: Modals for Editing

Create modal dialogs (hidden by default, shown by adding a `.show` class) for:

**Session modal**: Fields for title, start time (`<input type="time">`), end time, session type (dropdown populated from `state.sessionTypes`), volunteer name, and room assignment (checkboxes for each room on the current tab, plus an "All Rooms" checkbox that hides the individual room checkboxes when checked). This modal is used for both adding and editing sessions.

**Manage Rooms modal**: Shows every room from the global `allRooms` registry with a checkbox indicating whether it appears on the current tab. Checking adds the room; unchecking removes it from this tab only. Each room also has Rename and Delete buttons. Rename edits the global room definition (propagates to all tabs). Delete permanently removes it from everywhere (with a confirmation showing how many tabs it's on). At the bottom, a form to create a new room (name + optional capacity) and add it to the current tab.

**Manage Session Types modal**: Lists all session types with an inline `<input type="color">` picker for each (so users can click and change colors immediately), a Rename button, and a Delete button. At the bottom, a form to add new types with a name field and color picker. Built-in types cannot be deleted.

**Tab/Date modal**: Simple text input for the tab name. Used for both adding new tabs and renaming existing ones (via double-click on the tab).

**Right-click context menu**: When right-clicking a session block, show a small floating menu with Edit and Delete options. Hide it on any click elsewhere.

---

## Step 8: Tab Management

When adding a new tab, it should automatically include all existing rooms from the global registry. If no rooms exist yet, create a default "Room 1".

When renaming a tab (double-click), update the tab name in `state.dates`, and re-key both `state.sessions` and `state.tabRooms` from the old name to the new name.

When removing a tab, delete its entries from `state.sessions` and `state.tabRooms`. Require at least one tab to exist. Switch to the first remaining tab after deletion.

Make the active tab visually distinct with a colored background (e.g., #3498db blue), white text, bold font weight, and a bottom border accent.

---

## Step 9: JSON Save/Load

**Save**: Serialize `dates`, `allRooms`, `tabRooms`, `sessions`, and `sessionTypes` to JSON. Include a `version: 2` field. Create a Blob, generate an object URL, and trigger a download via a temporary `<a>` element.

**Load**: Use a hidden `<input type="file" accept=".json">`. On file selection, read with FileReader, parse JSON, and populate state. Support backward compatibility: if the loaded file has `version: 1` (or no version) with the old per-tab room objects format (`rooms: { tabName: [roomObjects] }`), migrate it by extracting unique rooms into `allRooms` and converting per-tab arrays to ID lists in `tabRooms`. After loading, recalculate `nextRoomId` to be higher than any existing room ID.

---

## Step 10: Suggested Session Type Defaults

Pre-populate these session types (users can add/edit/delete from here):

| Type ID | Label | Color |
|---------|-------|-------|
| admin-time | Admin Time | #c55a11 (brown/orange) |
| social-networking | Social/Networking | #ff9900 (orange) |
| passing-time | Passing Time | #00ffff (cyan) |
| session | Session | #b6d7a8 (light green) |
| open-space | Open Space | #a4c2f4 (light blue) |
| sponsor | Sponsor | #ffe599 (light yellow) |

---

## Common Pitfalls to Avoid

These are issues that came up during the original development. Mentioning them upfront should help avoid multiple revision cycles:

1. **Don't double-count scroll offset in drop handlers.** `getBoundingClientRect()` returns coordinates relative to the viewport, already accounting for scroll. Do NOT add `scrollContainer.scrollTop` on top of it.

2. **Use `Math.round()` for slot snapping, not `Math.floor()`.** Floor causes the session to always snap to the slot above where you drop it, which feels imprecise.

3. **Track the drag grab offset.** Without `dragOffsetY`, sessions snap their top edge to the cursor position instead of maintaining the relative grab point. Record it on dragstart, subtract it on drop.

4. **Put everything in a single scroll container.** If the time column and room columns are in separate scroll containers, they won't scroll together. Use one `overflow: auto` container with sticky positioning on the time column and room headers.

5. **Use flex row layout for room columns.** Without `display: flex` on the grid container, room columns stack vertically instead of appearing side by side.

6. **Render "all rooms" sessions inside each room column** (not as a separate overlay). This keeps them aligned with the grid and scrolling correctly.

7. **Grid line alignment**: Use `border-top` (not `border-bottom`) on time labels, and match the room body's `repeating-linear-gradient` to the same intervals. The first gradient line should start at 0px.

8. **Inline color pickers work better than hidden ones.** Programmatically calling `.click()` on a dynamically created hidden `<input type="color">` is unreliable across browsers. Instead, put the color input directly in the UI.

9. **No localStorage/sessionStorage.** If this will be used in certain sandboxed environments (like Claude artifacts), browser storage APIs are unavailable. Keep all state in JavaScript variables and use JSON file save/load for persistence.

---

## Testing Checklist

After building, verify these behaviors:

- [ ] Sessions can be dragged between rooms and snap to 5-minute increments
- [ ] Dragging a session preserves its duration
- [ ] Grabbing a session in the middle doesn't jump the top edge to the cursor
- [ ] Time column stays visible when scrolling right
- [ ] Room headers stay visible when scrolling down
- [ ] Multiple overlapping sessions in the same room display side by side
- [ ] "All Rooms" sessions appear in every room column and are not draggable
- [ ] Creating a new tab includes all existing rooms
- [ ] Removing a room from a tab doesn't delete it from other tabs
- [ ] Renaming a room in Manage Rooms updates it everywhere
- [ ] Session type colors can be changed with the inline color picker
- [ ] Saving and loading JSON preserves all state correctly
- [ ] Tabs can be renamed by double-clicking
- [ ] Room names can be renamed by double-clicking the column header
- [ ] Right-clicking a session shows Edit/Delete options
