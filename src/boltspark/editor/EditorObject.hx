package boltspark.editor;

import boltspark.project.StableId;

/** Pure scene object model owned by one EditorSession. */
class EditorObject {
    public final id:Int;
    public final persistentId:String;
    public var name:String;
    public final kind:EditorObjectKind;
    public var scene(default, null):Null<EditorSession>;
    public var parent(default, null):Null<EditorObject>;
    /** Ordered immediate children. Mutations are owned by SceneHierarchy. */
    public final children:Array<EditorObject> = [];
    public var transform(get, set):EditorTransform;

    var localTransform:EditorTransform;

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
            transform:EditorTransform, kind:EditorObjectKind = Cube,
            ?scene:EditorSession) {
        if (id < 1) throw "Editor object runtime ID must be positive";
        this.id = id;
        this.persistentId = StableId.require(persistentId,
            "editorObject.persistentId");
        this.name = requireName(name);
        this.kind = EditorObjectKind.require(kind);
        this.scene = scene;
        setTransformInternal(transform == null ? new EditorTransform() : transform);
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

    function get_localTransformMatrix():TransformMatrix {
        return localTransform.toMatrix();
    }

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

    function get_transform():EditorTransform return localTransform;

    function set_transform(value:EditorTransform):EditorTransform {
        setTransformInternal(value == null ? new EditorTransform() : value);
        return localTransform;
    }

    function setTransformInternal(value:EditorTransform):Void {
        var next = value.clone();
        if (localTransform != null) localTransform.onChanged = null;
        localTransform = next;
        var owner = this;
        localTransform.onChanged = function() {
            // Descendants observe this through the parent's world revision;
            // no subtree walk is required.
            owner.cachedWorldTransformRevision = -1;
        };
        worldCacheInitialized = false;
        cachedWorldTransformRevision = -1;
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

    public static function requireName(value:String):String {
        if (value == null) throw "Editor object name cannot be null";
        var normalized = StringTools.trim(value);
        if (normalized.length == 0) throw "Editor object name cannot be empty";
        return normalized;
    }

    function requireScene():EditorSession {
        if (scene == null) throw 'Editor object ${persistentId} is not in a scene';
        return scene;
    }
}
