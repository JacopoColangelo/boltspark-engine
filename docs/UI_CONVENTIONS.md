# BoltUI conventions

These are deliberate, stable rules for the editor UI. New panels and widgets
should follow them instead of inventing local variants.

## Cursor

- **Arrow (`hxd.Cursor.Default`) is the only cursor for clickable UI.** Buttons,
  menu rows, tiles, folder rows, popovers, tab strips, and full-window dismiss
  catches all keep the arrow. There is no web-style pointing hand.
- `h2d.Interactive` defaults to a button/hand cursor, so **every interactive set
  in BoltUI must assign `cursor` explicitly**. This includes invisible catches
  that cover the window: a forgotten cursor assignment shows up as a stray hand
  over otherwise ordinary UI.
- Only true resize affordances use a different cursor (`hxd.Cursor.ResizeLeftRight`
  on the folder splitter, etc.). Text inputs keep the text cursor supplied by
  `TextInput`.

## Surfaces and chrome

- Flat square surfaces; structure comes from one-pixel borders and inset fields,
  never gradients, shadows used as decoration, or web-style rounded cards.
- Popovers use `Theme.PANEL_ALT` with `Theme.BORDER_STRONG`; their header strip
  uses `Theme.PANEL_HEADER`. Menu panels and popovers must keep a complete frame
  on all four sides — row backgrounds are inset by the panel padding so they
  never paint over the border.
- Selection, focus, active tools, and slider fills use `Theme.ACCENT`; muted
  selected backgrounds use `Theme.ACCENT_MUTED`.

## Menus and popovers

- `MenuDropdown` rows are 22 px with a 3 px panel padding. Any outside left-click
  dismisses the menu. Cascading submenus open on hover and flip left when the
  parent is near the window edge.
- Group menu actions by intent with thin separator rows (`separator: true`):
  create, edit, structure, destroy. Omit entries that cannot apply — for example
  Paste without a clipboard, Unparent on a root object, or Expand on a leaf.
  A menu of three relevant actions is better than nine greyed-out ones.
- **`MenuDropdown` cascades to any depth.** Group related creation actions under
  one top-level entry instead of cluttering the menu (Scene Hierarchy:
  `Create New...` → `Empty Game Object` / `Primitives` → primitive list).
- Menus are short by design. When a menu grows, split it into a second labelled
  button rather than adding section headers to an existing one (Asset Browser
  Filter and Sort are the reference).
- A popover has one full-window dismiss catch behind it. The catch is invisible
  and must use the arrow cursor.

## Typography and alignment

- `ctx.font` (13 px regular) for body labels, `ctx.semiboldFont` (13 px) for
  headings and buttons, `ctx.captionFont` (11 px semibold) for captions, values,
  and compact metadata.
- Controls in a row share the same left edge. In a compact popover, all content
  starts at the same 12 px inset; the value field sits at the matching right
  inset.
- A search field's icon and input text use the same vertical centering metric so
  the placeholder never sits a pixel off from the magnifier.

## Interaction

- No hover tooltips in dense panels; labels and icons must be self-explanatory.
- A plain click never starts a drag; the drag ghost appears only after the
  pointer moves past the drag threshold.
- Desktop editor controls keep the arrow cursor and avoid hand/zoom cursors.
- Destructive actions require confirmation; copy/paste, drag/drop, and folder
  navigation behave the same in every panel that offers them.
- Keyboard shortcuts are contextual to the focused panel and must not fire while
  a text field owns keyboard focus.

## Icons

- Icons come from the pinned Tabler atlas (`UiIcons`) or the dedicated larger
  masks (for example `scene_thumb.png`). Reuse an icon only when its meaning
  matches; add a pinned glyph instead of overloading an unrelated one.
- Object visibility uses `Eye` / `EyeOff` at the right edge of hierarchy rows.
  The inspector's `Enabled` flag uses the flat `UiCheckbox` (inset field, accent
  check) directly under the name row.
