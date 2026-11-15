package boltspark.editor;

import boltspark.engine.Component;
import boltspark.engine.GameObject;
import boltspark.project.StableId;

/** Generic GameObject plus editor-only identity, hierarchy, and world caches. */
class EditorObject extends GameObject {
    public final id:Int;
    public final persistentId:String;
    public var scene(default, null):Null<EditorSession>;
    public var parent(default, null):Null<EditorObject>;
    /** Ordered immediate children. Mutations are owned by SceneHierarchy. */
    public final children:Array<EditorObject> = [];

    // Lazy world-cache state. SceneHierarchy is the only writer.
    @:noCompletion public var worldCacheInitialized:Bool = false;
    @:noCompletion public var cachedParent:Null<EditorObject>;
    @:noCompletion public var cachedParentRevision:Int = -1;
    @:noCompletion public var cachedLocalRevision:Int = -1;
    @:noCompletion public var cachedWorldMatrix:TransformMatrix;
    @:noCompletion public var worldRevision:Int = 0;
    @:noCompletion public var cachedWorldTransform:EditorTransform;
    @:noCompletion public var cachedWorldTransformRevision:Int = -1;

    public function new(id:Int, persistentId:String, name:String,
            transform:EditorTransform, ?components:Array<Component>,
            ?scene:EditorSession) {
        if (id < 1) throw "Editor object runtime ID must be positive";
        super(name, transform == null ? new EditorTransform() : transform);
        this.id = id;
        this.persistentId = StableId.require(persistentId,
            "editorObject.persistentId");
        this.scene = scene;
        if (components != null) {
            for (component in components) addComponent(component);
        }
    }

    public var localTransformMatrix(get, never):TransformMatrix;
    public var worldTransformMatrix(get, never):TransformMatrix;
    public var worldTransform(get, never):EditorTransform;
    public var worldPositionX(get, never):Float;
    public var worldPositionY(get, never):Float;
    public var worldPositionZ(get, never):Float;
    public var worldRotationX(get, never):Float;
    public var worldRotationY(get, never):Float;
    public var worldRotationZ(get, never):Float;
    public var worldRotationW(get, never):Float;
    public var worldScaleX(get, never):Float;
    public var worldScaleY(get, never):Float;
    public var worldScaleZ(get, never):Float;
    public var siblingIndex(get, never):Int;
    public var depth(get, never):Int;

    function get_localTransformMatrix():TransformMatrix return transform.toMatrix();
    function get_worldTransformMatrix():TransformMatrix {
        return requireScene().hierarchy.worldMatrix(this);
    }
    function get_worldTransform():EditorTransform {
        return requireScene().hierarchy.worldTransform(this);
    }
    inline function get_worldPositionX():Float return worldTransform.positionX;
    inline function get_worldPositionY():Float return worldTransform.positionY;
    inline function get_worldPositionZ():Float return worldTransform.positionZ;
    inline function get_worldRotationX():Float return worldTransform.rotationX;
    inline function get_worldRotationY():Float return worldTransform.rotationY;
    inline function get_worldRotationZ():Float return worldTransform.rotationZ;
    inline function get_worldRotationW():Float return worldTransform.rotationW;
    inline function get_worldScaleX():Float return worldTransform.scaleX;
    inline function get_worldScaleY():Float return worldTransform.scaleY;
    inline function get_worldScaleZ():Float return worldTransform.scaleZ;

    function get_siblingIndex():Int {
        return scene == null ? -1 : scene.hierarchy.siblingIndex(this);
    }

    function get_depth():Int {
        return scene == null ? 0 : scene.hierarchy.depth(this);
    }

    override public function componentChanged(component:Component):Void {
        if (component == transform) {
            worldCacheInitialized = false;
            cachedWorldTransformRevision = -1;
        }
    }

    @:noCompletion public function hierarchySetScene(value:Null<EditorSession>):Void {
        scene = value;
        worldCacheInitialized = false;
        cachedWorldTransformRevision = -1;
    }

    @:noCompletion public function hierarchySetParent(value:Null<EditorObject>):Void {
        parent = value;
        worldCacheInitialized = false;
        cachedWorldTransformRevision = -1;
    }

    public function isAncestorOf(other:EditorObject):Bool {
        if (other == null || scene == null || other.scene != scene) return false;
        var current = other.parent;
        while (current != null) {
            if (current == this) return true;
            current = current.parent;
        }
        return false;
    }

    /** Source-compatible validation entry point for editor commands. */
    public static inline function requireName(value:String):String {
        return GameObject.requireName(value);
    }

    function requireScene():EditorSession {
        if (scene == null) throw 'Editor object ${persistentId} is not in a scene';
        return scene;
    }
}
