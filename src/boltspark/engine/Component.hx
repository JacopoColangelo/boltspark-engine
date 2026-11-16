package boltspark.engine;

import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.project.ComponentData;

/**
 * Base class for behavior and data attached to a GameObject.
 *
 * Components are constructed detached, acquire exactly one owner through
 * GameObject.addComponent(), and are destroyed when removed or with their
 * owner. A destroyed component cannot be attached again; snapshots clone it.
 */
class Component {
    public var gameObject(default, null):Null<GameObject>;
    public var enabled:Bool = true;
    public var started(default, null):Bool = false;
    public var destroyed(default, null):Bool = false;

    public var transform(get, never):Null<Transform>;
    public var typeId(get, never):String;
    public var displayName(get, never):String;

    public function new() {}

    inline function get_transform():Null<Transform> {
        return gameObject == null ? null : gameObject.transform;
    }

    function get_typeId():String {
        return Type.getClassName(Type.getClass(this));
    }

    function get_displayName():String return typeId;

    /** Called once before the first update while attached to a started owner. */
    public function onStart():Void {}

    /** Called by GameObject.update() while this component is enabled. */
    public function onUpdate(dt:Float):Void {}

    /** Called exactly once before ownership is cleared. */
    public function onDestroy():Void {}

    /** Create a detached copy suitable for undo, duplication, and copy/paste. */
    public function cloneComponent():Component {
        throw '${typeId} must override cloneComponent()';
    }

    /** Component-owned, UI-neutral Inspector property definitions. */
    public function inspectorData(componentIndex:Int):ComponentInspectorData {
        return new ComponentInspectorData(componentIndex, typeId, displayName);
    }

    /** Optional generic Inspector mutation hooks for future component types. */
    public function setInspectorNumber(propertyId:String, axis:Int,
            value:Float):Bool return false;
    public function setInspectorText(propertyId:String, value:String):Bool return false;
    /** Assign a reusable asset reference by id (empty id means "none"). */
    public function setInspectorAsset(propertyId:String, assetId:String):Bool return false;
    /** Toggle a boolean Inspector property. */
    public function setInspectorBool(propertyId:String, value:Bool):Bool return false;
    public function resetInspectorProperty(propertyId:String):Bool return false;
    public function setInspectorLinked(propertyId:String, linked:Bool):Bool return false;

    /** Versioned scene envelope, or null for non-serialized built-ins. */
    public function toComponentData():Null<ComponentData> return null;

    /** Notify an owning GameObject that component state changed. */
    public function changed():Void {
        if (gameObject != null) gameObject.componentChanged(this);
    }

    @:allow(boltspark.engine.GameObject)
    function attach(owner:GameObject):Void {
        if (owner == null) throw "Cannot attach a Component to a null GameObject";
        if (destroyed) throw '${typeId} has already been destroyed';
        if (gameObject != null) throw '${typeId} is already attached to a GameObject';
        gameObject = owner;
    }

    @:allow(boltspark.engine.GameObject)
    function startInternal():Void {
        if (destroyed || started) return;
        started = true;
        onStart();
    }

    @:allow(boltspark.engine.GameObject)
    function updateInternal(dt:Float):Void {
        if (!destroyed && started && enabled) onUpdate(dt);
    }

    @:allow(boltspark.engine.GameObject)
    function destroyInternal():Void {
        if (destroyed) return;
        destroyed = true;
        onDestroy();
        gameObject = null;
    }

    /** JSON-compatible deep copy used by versioned component payloads. */
    public static function copyData(value:Dynamic):Dynamic {
        if (value == null) return {};
        return haxe.Json.parse(haxe.Json.stringify(value));
    }
}
