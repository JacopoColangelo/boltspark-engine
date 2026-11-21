# Initial Boltspark project and scene contracts

This document describes the **versioned data foundation**, its current
component mapping, and the integrated project-session layer that exposes it to
the editor's File menu.

## Files and schemas

- Project manifest: `*.boltproject`, schema version `1`.
- Scene document: `*.boltscene`, schema version `1`.
- Implementations: `src/boltspark/project/ProjectCodec.hx` and
  `src/boltspark/project/SceneCodec.hx`.
- Round-trip fixtures: `tests/fixtures/project/`.

Both roots carry an integer `version`. An unsupported version is rejected
instead of being guessed or silently rewritten.

## Stable identities

Project, scene, asset, and entity IDs are lowercase 128-bit values represented
as exactly 32 hexadecimal characters. Runtime hierarchy selection may continue
to use compact integer handles, but `SceneObject.persistentId` is the durable
identity intended for serialization and references.

IDs are validated for uniqueness within each document. Scene parent references
must resolve, self-parenting and parent cycles are rejected, and a project's
`defaultSceneId` must resolve to an asset whose type is `scene`.

## Paths

Serialized asset paths are project-relative and use `/` separators. Empty,
absolute, drive-qualified, and `..` traversal paths are rejected by
`ProjectPath.normalizeRelative`. `ProjectSession` resolves them against the
manifest's directory and rejects scene files chosen outside the project root.

## Scene entities and components

Every entity contains:

- stable `id`, display `name`, and nullable `parentId`;
- Position, editor Rotator, and signed non-zero Scale values;
- optional exact quaternion, affine shear, and Rotator-hint-validity fields
  written by the editor (legacy schema-1 readers can continue using the TRS
  fields, while Boltspark can reconstruct world-preserving nested transforms);
- an array of versioned component envelopes.

A component envelope has `type`, integer `version`, and object-valued `data`.
Individual component payload schemas can therefore evolve independently of the
scene root. The mandatory runtime Transform continues to map to the schema-1
top-level `transform` object for backward compatibility. Other attached
components map to envelopes through `ComponentRegistry`. The existing
`meshRenderer { primitive: "cube" }` fixture loads as a real MeshRenderer and
is written back with additive generic mesh/material identities.

Unknown component types and unknown fields on known component envelopes remain
preserved. This lets an older editor retain newer component data even when it
cannot instantiate that component's behavior.

## Compatibility and safety

Unknown fields on projects, assets, scenes, entities, and component envelopes
are retained through decode/encode so a newer producer's data is not silently
destroyed by a partial reader. Known fields are always validated and rewritten
from the typed model.

`DocumentStore` writes a sibling `.tmp`, moves the previous document to `.bak`,
then atomically promotes the new file. If promotion fails, it attempts to
restore the previous document. Migrations and a user-facing recovery workflow
remain future M3 work.

## Command foundation

`src/boltspark/editor/commands/` provides bounded execute/undo/redo history,
redo-branch invalidation, and composite commands with rollback if a child fails.
`EditorSession` owns renderer-independent objects and an ordered scene graph.
Create, recursive delete, duplicate, reparent/reorder, rename, and transform
changes use concrete commands. Inspector scrubs and gizmo previews commit as one
transform command; structural undo restores durable IDs, parent/sibling order,
exact local affine state, and selection.

`SceneSerializer` maps this graph to and from `SceneDocument`. Entities are
written in stable hierarchy pre-order; loading constructs every object before a
second safe parenting pass, so a valid document may reference a parent that
appears later in its entity array. Scene duplication remaps every scene/entity
identity and parent reference.

## Integrated project session

`src/boltspark/project/ProjectSession.hx` is the missing session layer between
these contracts and the editor. It owns the current manifest/scene documents,
their absolute paths, the project-relative scene source, and a dirty flag; it
resolves asset paths against the manifest directory, keeps the default scene
asset registered, captures the editor graph through `SceneSerializer`, and
rebuilds a fresh `EditorSession` on open. Native Windows file dialogs live in
`Main` (using `hl.UI.loadFile`/`saveFile` from the already-bundled `ui.hdll`);
all writes still go through `DocumentStore`. The File menu exposes New/Open/
Save Project, Save Project As, and New/Open/Save Scene, and the title strip
shows the project and scene names with an unsaved marker.

Each project can hold multiple scenes. New Scene allocates a fresh durable
identity, a unique display name (`Main Scene`, `Main Scene 2`, …), and a unique
`Scenes/…boltscene` source so it never overwrites an existing scene or rebinds
its asset. Previously created scenes remain registered in the manifest and on
disk. The docked **Asset Browser** replaces the old modal scene manager: it
scans real `.boltscene` files under the project root (including unregistered
ones), groups them by folder, and supports Add → Scene, double-click Open,
inline Rename, and Delete. The File menu is limited to project operations plus
saving the current scene. Rename changes the document name, source, asset, and
file together (with collision suffixes), repointing the manifest before removing
the old file. Delete removes the asset and file, switches to a remaining scene
when the active one is removed, and refuses to remove the last scene. Both keep
`defaultSceneId` resolvable.

`DocumentStore.read` strips a UTF-8 BOM before decoding, so manifests and scenes
edited by common Windows text editors still load. A `.boltproject` path passed
as the editor's command-line argument (or `--project=…`) opens at startup; the
opt-in `tools/setup/register-project-association.ps1` writes only user-level HKCU
classes so double-clicking the file can use that path.
