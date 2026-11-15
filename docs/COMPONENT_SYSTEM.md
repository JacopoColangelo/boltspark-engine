# GameObject component system

Boltspark scene behavior is composed from `src/boltspark/engine/` components.
A `GameObject` is a generic name plus an ordered component collection. It does
not encode cube, sphere, camera, light, or other object kinds.

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

A cube is a normal GameObject configured by a factory:

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
component section does not require a GameObject-type check. Numeric, text,
reset, and link commands route back through `Main`; custom components may
override the corresponding `setInspector*` methods.

Serializable component types register factories with `ComponentRegistry` and
return a versioned `ComponentData` from `toComponentData()`. Transform remains
in the scene schema's top-level `transform` field for schema-1 compatibility.
Unknown component envelopes are represented by `UnknownComponent` and retained
without discarding their payload or extra fields.
