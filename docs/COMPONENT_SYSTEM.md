# GameObject component system

Boltspark scene behavior is composed from `src/boltspark/engine/` components.
A `GameObject` is a generic name plus an ordered component collection. Behavior
stays component-based, but every object exposes a stable `objectType`. Renderable
objects report the `Mesh3D` type (via `Mesh3D` / `EditorMesh3D`), so systems can
ask what kind of object something is without depending on a concrete class.

## Core API

Every GameObject creates one mandatory `Transform` at component index zero.
It cannot be removed or replaced, but its affine value can be edited through
the component. Other component instances are constructed detached and acquire
one owner when attached.

```haxe
import boltspark.engine.GameObject;
import boltspark.engine.MeshRenderer;

var object = new GameObject("GameObject");
var renderer = object.addComponent(new MeshRenderer());

var firstRenderer = object.getComponent(MeshRenderer);
var allRenderers = object.getComponents(MeshRenderer);
object.removeComponentInstance(renderer);
```

`addComponentType(MyComponent)` is available for component classes with a
no-argument constructor. `components` preserves attachment order, while
`getAllComponents()` returns a safe collection copy.

## Empty and primitive GameObjects

An empty object has only its identity Transform. Its position is `(0, 0, 0)`;
the editor grid is drawn at the real origin rather than half a cube below it.

```haxe
var empty = new GameObject("GameObject");
```

A cube is a Mesh3D configured by a factory:

```haxe
import boltspark.engine.PrimitiveGameObjects;

var cube = PrimitiveGameObjects.createCube("Cube");
// Transform
// MeshRenderer
//   Mesh     = Primitive Cube
//   Material = Default Material
```

Editor-session creation uses the same fresh component preset:

```haxe
session.createObject("Cube", new EditorTransform(), -1,
    PrimitiveGameObjects.cubeComponents());
```

`MeshRenderer.mesh` accepts any registered `Mesh`, and
`MeshRenderer.material` accepts any `Material`. `HeapsMeshFactory` maps mesh
asset IDs to concrete Heaps primitives; adding another primitive does not
require a new GameObject class.

`Mesh3D.is(object)` recognizes both runtime `Mesh3D` instances and editor scene
objects whose components include a `MeshRenderer`. Editor object construction
runs through `EditorObjectFactory`, so creation, undo/redo, duplication, and
scene loading all preserve that type identity.

Meshes and materials are **reusable asset references**, not scene objects:
`PrimitiveMeshes.all()` lists the built-in Cube, Sphere, Cylinder, Capsule, and
Plane assets (and any future imported static meshes registered with
`PrimitiveMeshes.register()`), while `Material.all()` lists the built-in Default
Material plus any registered materials. A new `MeshRenderer` automatically uses
the Default Material when none is supplied. Each renderer owns its own
`h3d.scene.Mesh` and material instance; geometry is cached per (mesh asset id +
`PrimitiveSettings`) pair, so multiple entities can share a mesh/material asset
without sharing transforms or mutable renderer state.

### Primitive settings

Each primitive asset publishes its own geometry parameter schema via
`PrimitiveMeshes.parameters()` (sphere: sides/rings/radius; cylinder:
sides/radius/height plus a capped toggle; cube/plane/capsule: size fields).
Values live in `PrimitiveSettings` on the **renderer instance**, not on the
shared mesh asset, so two spheres may use different segment counts while still
referencing one mesh asset. MeshRenderer serializes them in an optional
`primitiveSettings` block of its component data and resets them to the
primitive's defaults whenever the mesh asset changes.

Every parameter row publishes a **reset action**
(`MeshRenderer.resetInspectorProperty` restores that one parameter to
`PrimitiveMeshes.defaultSettings()`), and all settings edits participate in
undo/redo: numeric gestures commit one `PrimitiveSettingsCommand` at gesture
end (scrub, typed value, or arrow step — never mid-drag), boolean toggles and
resets commit immediately, and multi-selection gestures commit a single
composite entry through `EditorSession.commitAppliedPrimitiveSettings`.

## Lifecycle and cleanup

Subclass `Component` and override only the lifecycle methods needed:

```haxe
class Spinner extends Component {
    override public function onStart():Void {}

    override public function onUpdate(dt:Float):Void {
        transform.rotationY += dt;
    }

    override public function onDestroy():Void {}

    override public function cloneComponent():Component {
        return new Spinner();
    }
}
```

`Main.update()` dispatches `EditorSession.update(dt)`, which starts and updates
attached components. Removing a component or deleting its owner calls
`onDestroy()` exactly once and clears ownership. Components added after their
owner starts receive `onStart()` immediately. Destroyed instances cannot be
reattached; undo/redo and duplication use `cloneComponent()`.

## Inspector and serialization extension

Components override `inspectorData()` to publish UI-neutral property metadata.
`ComponentInspectorSection` renders that metadata generically, so adding a
component section does not require a GameObject-type check. Numeric (scalar,
integer), boolean, text, asset-picker, reset, and link commands route back
through `Main`; custom components may override the corresponding
`setInspector*` methods, including `setInspectorAsset()` for type-aware object
pickers and `setInspectorBool()` for toggles. Asset properties publish their
accepted type plus their options, so the same picker works for meshes,
materials, and future asset families.

### Removing components in the editor

Each removable component section shows a trash action in its header. Clicking
it routes through `EditorSession.removeComponentAt()` and command history, so
removal is undoable and the detached instance receives `onDestroy()` exactly
once. The mandatory Transform publishes `removable = false` and gets no header
action. Like Add Component, removal is limited to a single selected object.

Serializable component types register factories with `ComponentRegistry` and
return a versioned `ComponentData` from `toComponentData()`. Transform remains
in the scene schema's top-level `transform` field for schema-1 compatibility.
Unknown component envelopes are represented by `UnknownComponent` and retained
without discarding their payload or extra fields.
