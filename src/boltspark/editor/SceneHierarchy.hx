package boltspark.editor;

/**
 * Authoritative ordered scene graph for one EditorSession.
 *
 * Hierarchy mutation is centralized here so parent/child/root relationships
 * cannot diverge. World matrices are evaluated lazily using transform and
 * parent revision stamps; moving a parent therefore performs no eager walk of
 * a potentially large subtree.
 */
class SceneHierarchy {
    public final scene:EditorSession;
    public final roots:Array<EditorObject> = [];

    var nextWorldRevision:Int = 1;

    public function new(scene:EditorSession) {
        if (scene == null) throw "SceneHierarchy requires an EditorSession";
        this.scene = scene;
    }

    public function canParent(object:EditorObject,
            newParent:Null<EditorObject>):Bool {
        if (object == null || object.scene != scene) return false;
        if (newParent == null) return true;
        if (newParent.scene != scene || newParent == object) return false;
        return !object.isAncestorOf(newParent);
    }

    public function requireCanParent(object:EditorObject,
            newParent:Null<EditorObject>):Void {
        if (object == null) throw "Cannot parent a null object";
        if (object.scene != scene) {
            throw 'Object ${object.persistentId} belongs to another scene';
        }
        if (newParent == object) throw 'Object ${object.persistentId} cannot parent itself';
        if (newParent != null && newParent.scene != scene) {
            throw 'Cannot parent ${object.persistentId} across scenes';
        }
        if (newParent != null && object.isAncestorOf(newParent)) {
            throw 'Cannot parent ${object.persistentId} to its descendant ${newParent.persistentId}';
        }
    }

    /** Internal structural operation used by deterministic commands. */
    @:noCompletion public function attach(object:EditorObject,
            newParent:Null<EditorObject>, siblingIndex:Int):Void {
        requireCanParent(object, newParent);
        detach(object);
        var siblings = newParent == null ? roots : newParent.children;
        var index = clampIndex(siblingIndex, siblings.length);
        siblings.insert(index, object);
        object.hierarchySetParent(newParent);
        object.worldCacheInitialized = false;
    }

    /** Remove an object from its current sibling collection without deleting it. */
    @:noCompletion public function detach(object:EditorObject):Void {
        if (object == null) return;
        requireObject(object);
        var siblings = object.parent == null ? roots : object.parent.children;
        siblings.remove(object);
        object.hierarchySetParent(null);
    }

    public function siblingIndex(object:EditorObject):Int {
        if (object == null || object.scene != scene) return -1;
        return (object.parent == null ? roots : object.parent.children).indexOf(object);
    }

    public function depth(object:EditorObject):Int {
        if (object == null || object.scene != scene) return 0;
        var result = 0;
        var current = object.parent;
        while (current != null) {
            result++;
            current = current.parent;
        }
        return result;
    }

    /** Stable pre-order traversal with no recursion. */
    public function flatten():Array<EditorObject> {
        var result:Array<EditorObject> = [];
        var stack:Array<EditorObject> = [];
        var index = roots.length - 1;
        while (index >= 0) stack.push(roots[index--]);
        while (stack.length > 0) {
            var object = stack.pop();
            result.push(object);
            index = object.children.length - 1;
            while (index >= 0) stack.push(object.children[index--]);
        }
        return result;
    }

    /** Object plus every descendant in stable pre-order. */
    public function subtree(object:EditorObject):Array<EditorObject> {
        if (object == null || object.scene != scene) return [];
        var result:Array<EditorObject> = [];
        var stack:Array<EditorObject> = [object];
        while (stack.length > 0) {
            var current = stack.pop();
            result.push(current);
            var index = current.children.length - 1;
            while (index >= 0) stack.push(current.children[index--]);
        }
        return result;
    }

    /**
     * Remove selected descendants when an ancestor is already selected, then
     * return the remaining objects in hierarchy display order.
     */
    public function topLevelSelection(objects:Array<EditorObject>):Array<EditorObject> {
        if (objects == null || objects.length == 0) return [];
        var selected:Map<Int, Bool> = [];
        for (object in objects) {
            if (object != null && object.scene == scene) selected.set(object.id, true);
        }
        var result:Array<EditorObject> = [];
        for (object in flatten()) {
            if (!selected.exists(object.id)) continue;
            var ancestor = object.parent;
            var nested = false;
            while (ancestor != null) {
                if (selected.exists(ancestor.id)) {
                    nested = true;
                    break;
                }
                ancestor = ancestor.parent;
            }
            if (!nested) result.push(object);
        }
        return result;
    }

    public function worldMatrix(object:EditorObject):TransformMatrix {
        requireObject(object);
        // Build the parent chain iteratively, then validate caches root-first.
        var chain:Array<EditorObject> = [];
        var current:Null<EditorObject> = object;
        while (current != null) {
            chain.push(current);
            current = current.parent;
        }
        var index = chain.length - 1;
        while (index >= 0) {
            current = chain[index--];
            var parent = current.parent;
            var parentRevision = parent == null ? 0 : parent.worldRevision;
            var localRevision = current.transform.revision;
            if (!current.worldCacheInitialized
                    || current.cachedParent != parent
                    || current.cachedParentRevision != parentRevision
                    || current.cachedLocalRevision != localRevision) {
                var local = current.transform.toMatrix();
                current.cachedWorldMatrix = parent == null
                    ? local
                    : parent.cachedWorldMatrix.multiplied(local);
                current.cachedParent = parent;
                current.cachedParentRevision = parentRevision;
                current.cachedLocalRevision = localRevision;
                current.worldCacheInitialized = true;
                current.worldRevision = nextWorldRevision++;
                current.cachedWorldTransformRevision = -1;
            }
        }
        return object.cachedWorldMatrix.clone();
    }

    public function worldTransform(object:EditorObject):EditorTransform {
        worldMatrix(object);
        if (object.cachedWorldTransformRevision != object.worldRevision
                || object.cachedWorldTransform == null) {
            object.cachedWorldTransform = EditorTransform.fromMatrix(
                object.cachedWorldMatrix, object.transform.value);
            object.cachedWorldTransformRevision = object.worldRevision;
        }
        return object.cachedWorldTransform.clone();
    }

    public function localMatrixForWorld(object:EditorObject,
            desiredWorld:TransformMatrix,
            ?newParent:EditorObject):TransformMatrix {
        requireObject(object);
        if (desiredWorld == null || !desiredWorld.isFinite()) {
            throw "Desired world transform must be finite";
        }
        var parent = newParent;
        if (parent != null) {
            if (parent.scene != scene) throw "Cannot use a parent from another scene";
            return worldMatrix(parent).inverse().multiplied(desiredWorld);
        }
        return desiredWorld.clone();
    }

    public function localTransformForWorld(object:EditorObject,
            desiredWorld:EditorTransform,
            ?newParent:EditorObject):EditorTransform {
        if (desiredWorld == null) throw "Desired world transform cannot be null";
        return EditorTransform.fromMatrix(localMatrixForWorld(object,
            desiredWorld.toMatrix(), newParent), object.transform.value);
    }

    /** Validate full graph consistency after loading or complex commands. */
    public function validate():Void {
        var visited:Map<Int, Bool> = [];
        var stack:Array<EditorObject> = [];
        var index = roots.length - 1;
        while (index >= 0) {
            var root = roots[index--];
            if (root.parent != null) throw 'Root ${root.persistentId} has a parent';
            stack.push(root);
        }
        while (stack.length > 0) {
            var object = stack.pop();
            if (object.scene != scene) {
                throw 'Object ${object.persistentId} belongs to another scene';
            }
            if (visited.exists(object.id)) {
                throw 'Hierarchy cycle or duplicate reference at ${object.persistentId}';
            }
            visited.set(object.id, true);
            index = object.children.length - 1;
            while (index >= 0) {
                var child = object.children[index--];
                if (child.parent != object) {
                    throw 'Child ${child.persistentId} has an inconsistent parent';
                }
                stack.push(child);
            }
        }
        for (object in scene.objects) {
            if (!visited.exists(object.id)) {
                throw 'Object ${object.persistentId} is unreachable from scene roots';
            }
        }
        if (visited.keys().hasNext() && flatten().length != scene.objects.length) {
            throw "Hierarchy object count does not match the scene";
        }
    }

    function requireObject(object:EditorObject):Void {
        if (object == null) throw "Hierarchy object cannot be null";
        if (object.scene != scene) {
            throw 'Object ${object.persistentId} does not belong to this scene';
        }
    }

    static inline function clampIndex(index:Int, length:Int):Int {
        if (index < 0) return 0;
        if (index > length) return length;
        return index;
    }
}
