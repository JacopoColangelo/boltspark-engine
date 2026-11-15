# Initial Boltspark project and scene contracts

This document describes the first **versioned data foundation**, not a claim
that project open/save UI or a complete component runtime is finished.

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
`ProjectPath.normalizeRelative`. Resolving those paths against a chosen project
root belongs to the later project-session integration layer.

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
scene root. The fixture currently demonstrates a `meshRenderer` envelope with
a cube primitive; it does not yet define the final renderer/component API.

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
identity and parent reference. Project open/save UI remains a later boundary.
