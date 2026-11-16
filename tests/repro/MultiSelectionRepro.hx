import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.editor.MultiInspectorData;
import boltspark.editor.SelectionClick;
import boltspark.editor.SharedGizmoDelta;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.engine.Transform;
import boltspark.engine.inspector.ComponentInspectorData;

/**
 * Headless coverage for multi-object selection, the shared gizmo delta, merged
 * Inspector data, and one-step composite transform history.
 */
class MultiSelectionRepro {
    static function main():Void {
        testSelectionClicks();
        testSharedDelta();
        testMergedInspector();
        testCompositeTransformHistory();
        Sys.println("[multi-selection] viewport selection, shared gizmo delta, "
            + "merged inspector, and composite transform history passed");
    }

    static function testSelectionClicks():Void {
        var first = SelectionClick.apply([], -1, 1, SelectionClickMode.Replace);
        assertTrue(first.ids.length == 1 && first.ids[0] == 1 && first.primary == 1,
            "plain click did not select the object");

        var toggledOn = SelectionClick.apply(first.ids, first.primary, 2,
            SelectionClickMode.Toggle);
        assertTrue(toggledOn.ids.length == 2 && toggledOn.primary == 2,
            "Ctrl+click did not add the object");

        var added = SelectionClick.apply(toggledOn.ids, toggledOn.primary, 3,
            SelectionClickMode.Add);
        assertTrue(added.ids.length == 3 && added.primary == 3,
            "Shift+click did not add the object");

        var toggledOff = SelectionClick.apply(added.ids, added.primary, 1,
            SelectionClickMode.Toggle);
        assertTrue(toggledOff.ids.length == 2 && toggledOff.ids.indexOf(1) < 0
            && toggledOff.primary == 3, "Ctrl+click did not remove the object");

        var cleared = SelectionClick.apply(toggledOff.ids, toggledOff.primary, -1,
            SelectionClickMode.Replace);
        assertTrue(cleared.ids.length == 0 && cleared.primary == -1,
            "empty-space click did not clear the selection");
    }

    static function testSharedDelta():Void {
        var pivotStart = new EditorTransform();
        var object = new EditorTransform(1, 2, 0);

        var movedPivot = new EditorTransform(3, 0, 0);
        var moved = SharedGizmoDelta.apply(object, pivotStart, movedPivot,
            SharedGizmoDelta.MOVE);
        assertTrue(close(moved.positionX, 4) && close(moved.positionY, 2)
            && close(moved.positionZ, 0), "shared move did not translate the object");

        var rotatedPivot = new EditorTransform(0, 0, 0, 0, 0.7071067811865476,
            0, 0.7071067811865476);
        var rotated = SharedGizmoDelta.apply(new EditorTransform(1, 0, 0),
            pivotStart, rotatedPivot, SharedGizmoDelta.ROTATE);
        assertTrue(close(rotated.positionX, 0) && close(rotated.positionZ, -1),
            "shared rotate did not orbit the object around the pivot");
        assertTrue(close(rotated.rotationY, 0.7071067811865476)
            && close(rotated.rotationW, 0.7071067811865476),
            "shared rotate did not compose the pivot rotation delta");

        var scaledPivot = new EditorTransform(0, 0, 0, 0, 0, 0, 1,
            0, 0, 0, false, 2, 1, 1);
        var scaled = SharedGizmoDelta.apply(new EditorTransform(1, 0, 0, 0, 0, 0, 1,
            0, 0, 0, false, 1, 1, 1), pivotStart, scaledPivot,
            SharedGizmoDelta.SCALE);
        assertTrue(close(scaled.positionX, 2) && close(scaled.scaleX, 2)
            && close(scaled.scaleY, 1), "shared scale did not scale offset and size");
    }

    static function testMergedInspector():Void {
        var session = new EditorSession(8);
        var a = session.addInitialObject("A", null, null,
            PrimitiveGameObjects.cubeComponents());
        var b = session.createObject("B", new EditorTransform(5, 0, 0), -1,
            PrimitiveGameObjects.cubeComponents());
        var dataA = inspectorData(a);
        var dataB = inspectorData(b);
        var merged = MultiInspectorData.build(dataA, [dataA, dataB]);

        var transformSection:Null<ComponentInspectorData> = null;
        for (section in merged) {
            if (section.typeId == Transform.TYPE_ID) transformSection = section;
        }
        assertTrue(transformSection != null, "shared Transform section was dropped");
        var position = property(transformSection, "position");
        assertTrue(position != null && position.isMixed(0)
            && !position.isMixed(1) && !position.isMixed(2),
            "position X should be mixed while Y/Z are shared");
        assertTrue(close(position.numberValues[0], 0),
            "mixed property did not keep a valid primary edit base");
        var rotation = property(transformSection, "rotation");
        assertTrue(rotation != null && !rotation.isMixed(0)
            && !rotation.isMixed(1) && !rotation.isMixed(2),
            "identical rotation values should not be flagged as mixed");
    }

    static function testCompositeTransformHistory():Void {
        var session = new EditorSession(16);
        var a = session.addInitialObject("A", null, null,
            PrimitiveGameObjects.cubeComponents());
        var b = session.createObject("B", new EditorTransform(4, 0, 0), -1,
            PrimitiveGameObjects.cubeComponents());
        session.selectObjects([a.id, b.id], b.id);
        var beforeA = a.transform.clone();
        var beforeB = b.transform.clone();
        var afterA = beforeA.clone();
        afterA.positionZ = 2;
        var afterB = beforeB.clone();
        afterB.positionZ = 3;

        assertTrue(session.commitAppliedTransforms([a.id, b.id],
            [beforeA, beforeB], [afterA, afterB], "Move 2 objects"),
            "composite transform was not recorded");
        assertTrue(a.transform.sameAs(afterA) && b.transform.sameAs(afterB),
            "composite transform execute failed");
        assertTrue(session.history.undoLabel == "Move 2 objects",
            "composite transform used the wrong history label");
        assertTrue(session.undo() && a.transform.sameAs(beforeA)
            && b.transform.sameAs(beforeB), "composite transform undo failed");
        assertTrue(session.redo() && a.transform.sameAs(afterA)
            && b.transform.sameAs(afterB), "composite transform redo failed");
    }

    static function inspectorData(object:boltspark.editor.EditorObject)
            :Array<ComponentInspectorData> {
        return [for (index in 0...object.components.length)
            object.components[index].inspectorData(index)];
    }

    static function property(section:ComponentInspectorData, id:String)
            :Null<boltspark.engine.inspector.ComponentPropertyData> {
        if (section == null) return null;
        for (candidate in section.properties) {
            if (candidate.id == id) return candidate;
        }
        return null;
    }

    static function close(a:Float, b:Float):Bool {
        return Math.abs(a - b) <= 0.0001;
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
