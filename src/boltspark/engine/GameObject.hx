package boltspark.engine;

import boltspark.editor.EditorTransform;

/** Generic container whose behavior is entirely supplied by Components. */
class GameObject {
    public var name(get, set):String;
    /** Ordered component collection. Mutate it only through component methods. */
    public final components:Array<Component> = [];
    public var transform(default, null):Transform;
    public var started(default, null):Bool = false;
    public var destroyed(default, null):Bool = false;

    var objectName:String;

    public function new(name:String = "GameObject", ?initialTransform:EditorTransform) {
        objectName = requireName(name);
        transform = new Transform(initialTransform);
        attachComponent(transform, 0, true);
    }

    /** Attach an already-constructed component and return it for configuration. */
    public function addComponent<T:Component>(component:T):T {
        attachComponent(component, components.length, false);
        return component;
    }

    /** Construct and attach a no-argument component type. */
    public function addComponentType<T:Component>(type:Class<T>):T {
        if (type == null) throw "Component type cannot be null";
        return addComponent(Type.createInstance(type, []));
    }

    public function getComponent<T:Component>(type:Class<T>):Null<T> {
        if (type == null) return null;
        for (component in components) {
            if (Std.isOfType(component, type)) return cast component;
        }
        return null;
    }

    public function getComponents<T:Component>(?type:Class<T>):Array<T> {
        var result:Array<T> = [];
        for (component in components) {
            if (type == null || Std.isOfType(component, type)) {
                result.push(cast component);
            }
        }
        return result;
    }

    public inline function getAllComponents():Array<Component> {
        return components.copy();
    }

    public function removeComponent<T:Component>(type:Class<T>):Bool {
        var component = getComponent(type);
        return component != null && removeComponentInstance(component);
    }

    public function removeComponentInstance(component:Component):Bool {
        var index = components.indexOf(component);
        if (index < 0) return false;
        if (component == transform) throw "Transform is mandatory and cannot be removed";
        components.splice(index, 1);
        component.destroyInternal();
        componentChanged(component);
        return true;
    }

    /** Start all current components. Components added later start immediately. */
    public function start():Void {
        if (destroyed || started) return;
        started = true;
        for (component in components.copy()) component.startInternal();
    }

    public function update(dt:Float):Void {
        if (destroyed) return;
        if (!started) start();
        for (component in components.copy()) component.updateInternal(dt);
    }

    public function destroy():Void {
        if (destroyed) return;
        destroyed = true;
        var index = components.length - 1;
        while (index >= 0) components[index--].destroyInternal();
        components.resize(0);
    }

    /** Override in engine/editor projections that cache component-derived state. */
    public function componentChanged(component:Component):Void {}

    @:noCompletion public function insertComponent(component:Component,
            index:Int):Component {
        attachComponent(component, index, false);
        return component;
    }

    @:noCompletion public function removeComponentAt(index:Int):Component {
        if (index < 0 || index >= components.length) {
            throw 'Component index ${index} is out of range';
        }
        var component = components[index];
        if (component == transform) throw "Transform is mandatory and cannot be removed";
        components.splice(index, 1);
        component.destroyInternal();
        componentChanged(component);
        return component;
    }

    function attachComponent(component:Component, index:Int,
            allowTransform:Bool):Void {
        if (destroyed) throw "Cannot add a Component to a destroyed GameObject";
        if (component == null) throw "Cannot add a null Component";
        if (Std.isOfType(component, Transform) && !allowTransform) {
            throw "A GameObject has exactly one mandatory Transform";
        }
        component.attach(this);
        var target = Std.int(Math.max(0, Math.min(index, components.length)));
        components.insert(target, component);
        if (started) component.startInternal();
        componentChanged(component);
    }

    inline function get_name():String return objectName;
    function set_name(value:String):String return objectName = requireName(value);

    public static function requireName(value:String):String {
        if (value == null) throw "GameObject name cannot be null";
        var normalized = StringTools.trim(value);
        if (normalized.length == 0) throw "GameObject name cannot be empty";
        return normalized;
    }
}
