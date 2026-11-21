import boltspark.editor.EditorObject;
import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.editor.TransformMatrix;
import boltspark.engine.MeshRenderer;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.project.SceneCodec;
import boltspark.project.SceneSerializer;
import boltspark.project.StableId;

/** Headless scene-graph, affine-transform, command, and serialization regression. */
class SceneHierarchyRepro {
    static inline var EPSILON:Float = 0.00001;

    static function main():Void {
        testParentingAndTransforms();
        testReparentModesAndUndo();
        testSiblingPermutationUndo();
        testMultiObjectLifecycle();
        testDuplicateNaming();
        testUniqueNames();
        testCreateEmptyParentOrdering();
        testSerialization();
        testComplexUndoRedoSequence();
        testDeepHierarchy();
        Sys.println("[scene-hierarchy] parenting, affine transforms, drag semantics, undo, lifecycle, serialization, and deep nesting passed");
    }

    static function testParentingAndTransforms():Void {
        var euler = EditorTransform.fromEditorEulerDegrees(10, 20, 30);
        // Reference values captured from h3d.Quat.initRotation(30°, 20°, 10°).
        // Keeping the constants here lets this scene-model regression compile
        // without Heaps and protects the renderer-independent boundary.
        assertClose(euler.rotationX, 0.2392983377447303,
            "serialized Euler quaternion X mismatch");
        assertClose(euler.rotationY, 0.189307857412,
            "serialized Euler quaternion Y mismatch");
        assertClose(euler.rotationZ, 0.03813457647485015,
            "serialized Euler quaternion Z mismatch");
        assertClose(euler.rotationW, 0.9515485246437886,
            "serialized Euler quaternion W mismatch");

        var session = new EditorSession(64);
        var a = session.addInitialObject("A");
        var b = session.addInitialObject("B", new EditorTransform(1, 0, 0));
        var c = session.addInitialObject("C", new EditorTransform(0, 3, 0));
        var d = session.addInitialObject("D", new EditorTransform(0, 0, 4));
        assertTrue(session.reparentObjects([b.id], a.id, 0, false), "B -> A failed");
        assertTrue(session.reparentObjects([c.id], b.id, 0, false), "C -> B failed");
        assertTrue(session.reparentObjects([d.id], c.id, 0, false), "D -> C failed");
        assertTrue(a.children[0] == b && b.children[0] == c && c.children[0] == d,
            "deep parent/child references diverged");

        var threw = false;
        try session.reparentObjects([a.id], d.id, 0, true) catch (_:Dynamic) threw = true;
        assertTrue(threw, "descendant parenting was accepted");
        assertTrue(!session.canReparentObjects([a.id], d.id),
            "drop validation accepted a hierarchy cycle");

        // Parent translation, rotation, and scale all participate in child world space.
        a.transform.positionX = 10;
        a.transform.rotationZ = Math.sin(Math.PI * 0.25);
        a.transform.rotationW = Math.cos(Math.PI * 0.25);
        a.transform.scaleX = 2;
        a.transform.scaleY = 2;
        var bWorld = b.worldTransformMatrix.transformPoint(0, 0, 0);
        assertClose(bWorld.x, 10, "parent rotation changed child world X incorrectly");
        assertClose(bWorld.y, 2, "parent scale/rotation did not propagate to child");

        var previousC = c.worldTransformMatrix;
        b.transform.positionY = 5;
        assertTrue(!c.worldTransformMatrix.sameAs(previousC),
            "descendant world cache did not invalidate lazily");

        // Direct world editing derives a local transform through the parent inverse.
        var desired = c.worldTransform;
        desired.positionX += 7;
        desired.positionZ -= 2;
        assertTrue(session.transformWorldObject(c.id, desired, "Move C in World"),
            "world transform command was not recorded");
        assertMatrix(c.worldTransformMatrix, desired.toMatrix(),
            "world transform did not derive the correct local transform");
        session.hierarchy.validate();
    }

    static function testReparentModesAndUndo():Void {
        var session = new EditorSession(128);
        var left = session.addInitialObject("Left", transformedParent(2, -3, 1, 35, 2, 1, 0.5));
        var right = session.addInitialObject("Right", transformedParent(-4, 2, 6, -20, 0.75, 3, 1.5));
        var child = session.addInitialObject("Child",
            new EditorTransform(3, 4, -2, 0, 0, 0, 1,
                0, 0, 0, false, 1.2, 0.8, -1.1));
        session.reparentObjects([child.id], left.id, 0, false);
        var localBefore = child.transform.clone();
        var worldBefore = child.worldTransformMatrix;

        assertTrue(session.reparentObjects([child.id], right.id, 0, true),
            "world-preserving reparent failed");
        assertMatrix(child.worldTransformMatrix, worldBefore,
            "world-preserving reparent moved the object");
        assertTrue(Math.abs(child.transform.shearXY) > 0.000001
                || Math.abs(child.transform.shearXZ) > 0.000001
                || Math.abs(child.transform.shearYZ) > 0.000001,
            "non-uniform rotated reparent discarded required shear");

        var reparentedLocal = child.transform.clone();
        assertTrue(session.undo(), "reparent undo failed");
        assertTrue(child.parent == left && child.siblingIndex == 0,
            "reparent undo did not restore exact placement");
        assertTrue(child.transform.sameAs(localBefore),
            "reparent undo did not restore exact local transform");
        assertTrue(session.redo(), "reparent redo failed");
        assertTrue(child.parent == right && child.transform.sameAs(reparentedLocal),
            "reparent redo did not restore exact new state");

        var localPreserved = child.transform.clone();
        assertTrue(session.unparentObjects([child.id], false),
            "local-preserving unparent failed");
        assertTrue(child.parent == null && child.transform.sameAs(localPreserved),
            "explicit local-preserving operation changed local channels");

        var one = session.addInitialObject("One");
        var two = session.addInitialObject("Two");
        var three = session.addInitialObject("Three");
        three.transform.scaleY = -2;
        three.transform.shearXY = 0.2;
        var threeLocal = three.transform.clone();
        assertTrue(!session.unparentObjects([one.id]),
            "unparenting a root recorded a reorder command");
        assertTrue(session.hierarchy.roots.indexOf(one)
                < session.hierarchy.roots.indexOf(two),
            "unparenting a root changed sibling order");
        assertTrue(session.reparentObjects([three.id], -1, one.siblingIndex, true),
            "root sibling reorder failed");
        assertTrue(session.hierarchy.roots.indexOf(three) < session.hierarchy.roots.indexOf(one),
            "root sibling order was not updated");
        assertTrue(three.transform.sameAs(threeLocal),
            "same-parent reorder decomposed exact local transform channels");
        assertTrue(session.undo(), "sibling reorder undo failed");
        assertTrue(session.hierarchy.roots.indexOf(one) < session.hierarchy.roots.indexOf(two)
                && session.hierarchy.roots.indexOf(two) < session.hierarchy.roots.indexOf(three),
            "sibling reorder undo did not restore exact order");
    }

    static function testSiblingPermutationUndo():Void {
        // Exhaust every non-empty selection of five roots at every insertion
        // boundary. This catches index compression mistakes in multi-row drag,
        // including selections supplied in reverse order.
        for (mask in 1...32) {
            for (insertion in 0...6) {
                var session = new EditorSession(8);
                var objects:Array<EditorObject> = [];
                for (index in 0...5) {
                    objects.push(session.addInitialObject('P${index}'));
                }
                var ids:Array<Int> = [];
                var index = objects.length - 1;
                while (index >= 0) {
                    if ((mask & (1 << index)) != 0) ids.push(objects[index].id);
                    index--;
                }
                session.selectObjects(ids, ids[0]);
                var before = hierarchyIds(session);
                var changed = session.reparentObjects(ids, -1, insertion, true);
                var after = hierarchyIds(session);
                if (!changed) {
                    assertIntArrays(before, after,
                        "no-op sibling drag changed root order");
                    continue;
                }
                assertTrue(!sameIntArrays(before, after),
                    "sibling drag recorded history without changing order");
                assertTrue(session.undo(), "sibling permutation undo failed");
                assertIntArrays(hierarchyIds(session), before,
                    "sibling permutation undo changed exact root order");
                assertTrue(session.redo(), "sibling permutation redo failed");
                assertIntArrays(hierarchyIds(session), after,
                    "sibling permutation redo changed resulting root order");
            }
        }
    }

    static function testMultiObjectLifecycle():Void {
        var session = new EditorSession(128);
        var parent = session.addInitialObject("Parent");
        var child = session.addInitialObject("Child", new EditorTransform(1, 0, 0),
            null, PrimitiveGameObjects.cubeComponents(), parent.id);
        var grandchild = session.addInitialObject("Grandchild",
            new EditorTransform(0, 2, 0), null,
            PrimitiveGameObjects.cubeComponents(), child.id);
        var peer = session.addInitialObject("Peer", new EditorTransform(5, 0, 0));
        var target = session.addInitialObject("Target");

        // Selecting Parent + Child must move only Parent's subtree root once.
        assertTrue(session.reparentObjects([parent.id, child.id, peer.id],
            target.id, 0, true), "multi-object reparent failed");
        assertTrue(target.children.length == 2
                && target.children[0] == parent && target.children[1] == peer
                && child.parent == parent && grandchild.parent == child,
            "multi-object reparent duplicated or broke an internal subtree");
        assertTrue(session.undo(), "multi-object reparent undo failed");
        assertTrue(parent.parent == null && peer.parent == null
                && child.parent == parent && grandchild.parent == child,
            "multi-object reparent undo broke the original forest");
        assertTrue(session.redo(), "multi-object reparent redo failed");

        var duplicates = session.duplicateObjects([parent.id, child.id]);
        assertTrue(duplicates.length == 1, "selected descendant was duplicated twice");
        var duplicate = duplicates[0];
        assertTrue(duplicate.getComponent(MeshRenderer) == null
                && duplicate.children.length == 1
                && duplicate.children[0].getComponent(MeshRenderer) != null
                && duplicate.children[0].children.length == 1,
            "nested hierarchy components were not duplicated recursively");
        assertTrue(duplicate.persistentId != parent.persistentId
                && duplicate.children[0].persistentId != child.persistentId,
            "duplicate reused stable IDs");
        assertTrue(session.undo() && session.findObject(duplicate.id) == null,
            "duplicate undo failed");
        assertTrue(session.redo() && session.findObject(duplicate.id) != null,
            "duplicate redo failed");

        assertTrue(session.copyObjects([parent.id, child.id]), "copy failed");
        var pasted = session.pasteObjects(target.id);
        assertTrue(pasted.length == 1 && pasted[0].parent == target
                && pasted[0].children.length == 1,
            "paste did not retain subtree relationships");

        var emptyParent = session.createEmptyParent([peer.id], "Peer Group");
        assertTrue(emptyParent != null
                && emptyParent.getComponent(MeshRenderer) == null
                && peer.parent == emptyParent,
            "create-empty-parent transaction failed");
        assertTrue(session.undo() && session.findObject(emptyParent.id) == null
                && peer.parent == target,
            "create-empty-parent undo was not atomic");
        assertTrue(session.redo() && peer.parent == session.findObject(emptyParent.id),
            "create-empty-parent redo was not atomic");

        var objectCount = session.objects.length;
        var deleted = session.deleteObjects([parent.id, child.id]);
        assertTrue(deleted.length == 1 && session.findObject(parent.id) == null
                && session.findObject(child.id) == null
                && session.findObject(grandchild.id) == null,
            "parent deletion did not delete one complete subtree");
        assertTrue(session.undo() && session.objects.length == objectCount
                && session.findObject(parent.id).children[0].id == child.id
                && session.findObject(child.id).children[0].id == grandchild.id,
            "subtree deletion undo did not restore hierarchy/identity");
        assertTrue(session.redo() && session.findObject(parent.id) == null,
            "subtree deletion redo failed");
    }

    static function testDuplicateNaming():Void {
        var session = new EditorSession(32);
        var tree = session.addInitialObject("Tree");

        var first = session.duplicateObjects([tree.id])[0];
        var second = session.duplicateObjects([tree.id])[0];
        assertTrue(tree.name == "Tree" && first.name == "Tree (1)"
                && second.name == "Tree (2)",
            "duplicate names did not use sequential parenthesized suffixes");

        // Duplicating an already numbered object must continue its sequence,
        // not append a second suffix to the numbered name.
        var third = session.duplicateObjects([first.id])[0];
        assertTrue(third.name == "Tree (3)",
            "duplicating a numbered object did not continue the base sequence");

        assertTrue(session.copyObjects([tree.id]), "naming copy failed");
        var pasted = session.pasteObjects()[0];
        assertTrue(pasted.name == "Tree (4)",
            "paste did not share the duplicate naming convention");

        // Names generated in one command must participate in conflict checks
        // even though the command restores all snapshots only after naming.
        // Insertion now guarantees the two rocks are "Rock" and "Rock (1)".
        var rockA = session.addInitialObject("Rock");
        var rockB = session.addInitialObject("Rock");
        assertTrue(rockB.name == "Rock (1)",
            "initial insertion allowed duplicate names");
        var rocks = session.duplicateObjects([rockA.id, rockB.id]);
        assertTrue(rocks.length == 2 && rocks[0].name == "Rock (2)"
                && rocks[1].name == "Rock (3)",
            "multi-object duplicate generated conflicting names");
    }

    static function testUniqueNames():Void {
        var session = new EditorSession(32);

        // Creation suffixes conflicts instead of allowing two "Thing" objects.
        var first = session.createObject("Thing");
        var second = session.createObject("Thing");
        var third = session.createObject("Thing");
        assertTrue(first.name == "Thing" && second.name == "Thing (1)"
                && third.name == "Thing (2)",
            "creation did not resolve name conflicts with numeric suffixes");

        // Renaming to an occupied name continues the same sequence.
        var renamed = session.createObject("Other");
        assertTrue(session.renameObject(renamed.id, "Thing")
                && renamed.name == "Thing (3)",
            "rename did not resolve a conflicting name");

        // A free name is kept exactly as authored.
        var free = session.createObject("Free Name");
        assertTrue(free.name == "Free Name",
            "creation changed a name that was not in use");

        // Descendants of a duplicated subtree must be unique too.
        var parent = session.createObject("Parent");
        session.createChild(parent.id, "Branch");
        var clone = session.duplicateObjects([parent.id])[0];
        assertTrue(clone.name == "Parent (1)"
                && clone.children[0].name == "Branch (1)",
            "duplicated descendants reused their original names");

        // Scene-load style insertion resolves duplicates as well.
        var loaded = new EditorSession(8);
        var rockA = loaded.addInitialObject("Rock");
        var rockB = loaded.addInitialObject("Rock");
        assertTrue(rockA.name == "Rock" && rockB.name == "Rock (1)",
            "initial object insertion allowed duplicate names");
        loaded.hierarchy.validate();
    }

    static function testCreateEmptyParentOrdering():Void {
        var session = new EditorSession(32);
        var a = session.addInitialObject("A");
        var b = session.addInitialObject("B");
        var c = session.addInitialObject("C");
        var d = session.addInitialObject("D");
        var e = session.addInitialObject("E");
        b.transform.scaleY = -2;
        b.transform.shearXZ = 0.25;
        d.transform.rotationZ = 0.3;
        d.transform.rotationW = Math.sqrt(1 - 0.3 * 0.3);
        var bLocal = b.transform.clone();
        var dLocal = d.transform.clone();
        session.selectObjects([b.id, d.id], d.id);

        // Sparse selections expose temporary-parent ordering bugs: the group
        // must occupy the first selected slot, and undo must put C back between
        // B and D rather than restoring a compressed selected block.
        var group = session.createEmptyParent([d.id, b.id], "Sparse Group");
        assertTrue(group != null
                && session.hierarchy.roots[0] == a
                && session.hierarchy.roots[1] == group
                && session.hierarchy.roots[2] == c
                && session.hierarchy.roots[3] == e,
            "empty parent did not occupy the first selected sibling slot");
        assertTrue(group.children.length == 2
                && group.children[0] == b && group.children[1] == d,
            "empty parent did not retain sparse selection display order");
        assertTrue(b.transform.sameAs(bLocal) && d.transform.sameAs(dLocal),
            "same-parent grouping decomposed exact local transform channels");

        assertTrue(session.undo(), "sparse empty-parent undo failed");
        var roots = session.hierarchy.roots;
        assertTrue(roots.length == 5 && roots[0] == a && roots[1] == b
                && roots[2] == c && roots[3] == d && roots[4] == e,
            "sparse empty-parent undo changed exact sibling order");
        assertTrue(session.selectedObjectIds.length == 2
                && session.selectedObjectIds[0] == b.id
                && session.selectedObjectIds[1] == d.id
                && session.selectedObjectId == d.id,
            "sparse empty-parent undo changed the previous selection");

        assertTrue(session.redo(), "sparse empty-parent redo failed");
        group = session.findObject(group.id);
        assertTrue(group != null && session.hierarchy.roots[1] == group
                && group.children[0].id == b.id && group.children[1].id == d.id,
            "sparse empty-parent redo changed hierarchy order");
    }

    static function testSerialization():Void {
        var session = new EditorSession();
        var root = session.addInitialObject("Root", transformedParent(1, 2, 3, 15, 2, 1, 3),
            null, []);
        var child = session.addInitialObject("Child",
            new EditorTransform(4, 5, 6, 0.1, 0.2, 0.3, 0.9,
                10, 20, 30, true, -1, 2, 0.5, 0.2, -0.1, 0.3),
            null, PrimitiveGameObjects.cubeComponents(), root.id);
        var peer = session.addInitialObject("Peer", null, null,
            PrimitiveGameObjects.cubeComponents(), root.id);
        var sceneId = StableId.create("scene-test");
        var document = SceneSerializer.fromSession(session, sceneId, "Hierarchy Test");
        var encoded = SceneCodec.encode(document);
        var loaded = SceneSerializer.toSession(SceneCodec.decode(encoded));
        var loadedRoot = loaded.findObjectByPersistentId(root.persistentId);
        var loadedChild = loaded.findObjectByPersistentId(child.persistentId);
        var loadedPeer = loaded.findObjectByPersistentId(peer.persistentId);
        assertTrue(loadedRoot != null && loadedChild.parent == loadedRoot
                && loadedPeer.parent == loadedRoot
                && loadedRoot.children[0] == loadedChild
                && loadedRoot.children[1] == loadedPeer
                && loadedRoot.getComponent(MeshRenderer) == null
                && loadedChild.getComponent(MeshRenderer) != null,
            "scene load did not reconstruct parent and sibling order");
        assertTrue(loadedChild.transform.sameAs(child.transform),
            "scene round-trip changed exact local affine transform");
        assertTrue(loadedPeer.transform.sameAs(peer.transform),
            "scene round-trip changed rotation-hint validity");
        assertMatrix(loadedChild.worldTransformMatrix, child.worldTransformMatrix,
            "scene round-trip changed world transform");

        // Parent records are references, not an ordering requirement. Loading
        // must still work when a child appears before its parent in the file.
        var unordered = SceneCodec.decode(encoded);
        var childRecord = unordered.entities.splice(1, 1)[0];
        unordered.entities.unshift(childRecord);
        var unorderedSession = SceneSerializer.toSession(unordered);
        var unorderedChild = unorderedSession.findObjectByPersistentId(child.persistentId);
        var unorderedRoot = unorderedSession.findObjectByPersistentId(root.persistentId);
        assertTrue(unorderedChild.parent == unorderedRoot
                && unorderedRoot.children[0] == unorderedChild,
            "out-of-order scene records did not reconstruct hierarchy");

        var copy = SceneSerializer.duplicate(document, "Hierarchy Test Copy");
        assertTrue(copy.id != document.id && copy.entities.length == document.entities.length,
            "scene duplication did not create a new scene identity");
        for (index in 0...copy.entities.length) {
            assertTrue(copy.entities[index].id != document.entities[index].id,
                "scene duplication reused an entity stable ID");
        }
        var copySession = SceneSerializer.toSession(copy);
        assertTrue(copySession.hierarchy.roots[0].children.length == 2,
            "duplicated scene lost hierarchy relationships");
    }

    static function testDeepHierarchy():Void {
        var session = new EditorSession(8);
        var parent:EditorObject = null;
        var depth = 3000;
        for (index in 0...depth) {
            parent = session.addInitialObject('Node${index}',
                new EditorTransform(1, 0, 0), null, [],
                parent == null ? -1 : parent.id);
        }
        var world = parent.worldTransformMatrix.transformPoint(0, 0, 0);
        assertClose(world.x, depth, "deep iterative world transform was incorrect");
        assertTrue(session.hierarchy.flatten().length == depth,
            "deep iterative traversal lost objects");
        session.hierarchy.validate();

        var document = SceneSerializer.fromSession(session,
            StableId.create("deep-scene"), "Deep Hierarchy");
        var loaded = SceneSerializer.toSession(document, 8);
        var loadedFlat = loaded.hierarchy.flatten();
        assertTrue(loadedFlat.length == depth,
            "deep scene serialization lost objects");
        var loadedWorld = loadedFlat[loadedFlat.length - 1]
            .worldTransformMatrix.transformPoint(0, 0, 0);
        assertClose(loadedWorld.x, depth,
            "deep serialized hierarchy changed world transforms");
    }

    static function testComplexUndoRedoSequence():Void {
        var session = new EditorSession(64);
        var a = session.createObject("A");
        var b = session.createObject("B");
        var c = session.createObject("C");
        var d = session.createObject("D");
        session.reparentObjects([b.id], a.id, 0, false);
        session.reparentObjects([c.id], b.id, 0, false);
        session.reparentObjects([d.id], c.id, 0, false);

        var moveA = a.transform.clone();
        moveA.positionX = 12;
        moveA.positionY = -4;
        session.transformObject(a.id, moveA, "Move A");
        var rotateB = b.transform.clone();
        rotateB.rotationY = Math.sin(Math.PI * 0.125);
        rotateB.rotationW = Math.cos(Math.PI * 0.125);
        session.transformObject(b.id, rotateB, "Rotate B");
        var scaleC = c.transform.clone();
        scaleC.scaleX = 2;
        scaleC.scaleY = 0.5;
        scaleC.scaleZ = -1.5;
        session.transformObject(c.id, scaleC, "Scale C");
        session.reparentObjects([c.id], a.id, 1, true);

        var finalA = a.worldTransformMatrix;
        var finalB = b.worldTransformMatrix;
        var finalC = c.worldTransformMatrix;
        var finalD = d.worldTransformMatrix;
        var operations = 11;
        for (_ in 0...operations) {
            assertTrue(session.undo(), "complex sequence ran out of undo entries");
            session.hierarchy.validate();
        }
        assertTrue(session.objects.length == 0 && !session.history.canUndo,
            "undoing the complex sequence did not return to an empty scene");
        for (_ in 0...operations) {
            assertTrue(session.redo(), "complex sequence ran out of redo entries");
            session.hierarchy.validate();
        }
        a = session.findObject(a.id);
        b = session.findObject(b.id);
        c = session.findObject(c.id);
        d = session.findObject(d.id);
        assertTrue(b.parent == a && c.parent == a && d.parent == c,
            "complex redo did not restore final hierarchy");
        assertMatrix(a.worldTransformMatrix, finalA, "complex redo changed A world transform");
        assertMatrix(b.worldTransformMatrix, finalB, "complex redo changed B world transform");
        assertMatrix(c.worldTransformMatrix, finalC, "complex redo changed C world transform");
        assertMatrix(d.worldTransformMatrix, finalD, "complex redo changed D world transform");
    }

    static function transformedParent(x:Float, y:Float, z:Float,
            zDegrees:Float, sx:Float, sy:Float, sz:Float):EditorTransform {
        var radians = zDegrees * Math.PI / 180;
        return new EditorTransform(x, y, z, 0, 0,
            Math.sin(radians * 0.5), Math.cos(radians * 0.5),
            0, 0, zDegrees, true, sx, sy, sz);
    }

    static function assertMatrix(actual:TransformMatrix,
            expected:TransformMatrix, message:String):Void {
        if (!actual.sameAs(expected, EPSILON)) throw message;
    }

    static function assertClose(actual:Float, expected:Float,
            message:String):Void {
        if (!Math.isFinite(actual) || Math.abs(actual - expected) > EPSILON) {
            throw '${message}: expected ${expected}, got ${actual}';
        }
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }

    static function hierarchyIds(session:EditorSession):Array<Int> {
        return [for (object in session.hierarchy.flatten()) object.id];
    }

    static function sameIntArrays(a:Array<Int>, b:Array<Int>):Bool {
        if (a.length != b.length) return false;
        for (index in 0...a.length) if (a[index] != b[index]) return false;
        return true;
    }

    static function assertIntArrays(actual:Array<Int>, expected:Array<Int>,
            message:String):Void {
        if (!sameIntArrays(actual, expected)) {
            throw '${message}: expected ${expected.join(",")}, got ${actual.join(",")}';
        }
    }
}
