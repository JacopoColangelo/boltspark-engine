import boltspark.editor.EditorTransform;
import boltspark.editor.SceneObject;
import boltspark.editor.TransformMatrix;

/** Headless Heaps bridge regression for nested exact-affine render nodes. */
class SceneObjectAffineRepro {
    static inline var EPSILON:Float = 0.00001;

    static function main():Void {
        var parentNode = new h3d.scene.Object();
        var childNode = new h3d.scene.Object(parentNode);
        var parentView = new SceneObject(1, parentNode,
            "11111111111111111111111111111111");
        var childView = new SceneObject(2, childNode,
            "22222222222222222222222222222222");

        var parent = rotationZ(4, -3, 2, 31, 2, 0.75, -1.5);
        var child = rotationZ(1, 5, -2, -17, 1.2, -0.8, 2.1);
        child.shearXY = 0.35;
        child.shearXZ = -0.2;
        child.shearYZ = 0.15;
        parentView.applyTransform(parent);
        childView.applyTransform(child);

        assertHeapsMatrix(childNode.getAbsPos(),
            parent.toMatrix().multiplied(child.toMatrix()),
            "nested render matrix discarded affine shear");
        assertTrue(childView.captureTransform().sameAs(child),
            "render bridge did not capture exact authored channels");

        var nonUnit = child.clone();
        nonUnit.rotationX *= 7;
        nonUnit.rotationY *= 7;
        nonUnit.rotationZ *= 7;
        nonUnit.rotationW *= 7;
        childView.applyTransform(nonUnit);
        assertHeapsMatrix(childNode.getAbsPos(),
            parent.toMatrix().multiplied(nonUnit.toMatrix()),
            "render bridge did not normalize quaternion interpretation");
        childView.applyTransform(child);

        // Bounds containment and Inspector edits change editable TRS channels.
        // Capturing and reapplying must rebuild the shear correction around
        // those new channels instead of retaining a stale defaultTransform.
        childNode.x += 6;
        childNode.scaleY = -1.25;
        var edited = childView.captureTransform();
        childView.applyTransform(edited);
        assertHeapsMatrix(childNode.getAbsPos(),
            parent.toMatrix().multiplied(edited.toMatrix()),
            "edited nested channels retained a stale shear correction");

        var plain = new EditorTransform(2, 3, 4);
        childView.applyTransform(plain);
        assertTrue(childNode.defaultTransform == null,
            "non-sheared transform retained an affine correction");

        Sys.println("[scene-object-affine] nested shear application and correction rebuild passed");
    }

    static function rotationZ(x:Float, y:Float, z:Float, degrees:Float,
            sx:Float, sy:Float, sz:Float):EditorTransform {
        var radians = degrees * Math.PI / 180;
        return new EditorTransform(x, y, z, 0, 0,
            Math.sin(radians * 0.5), Math.cos(radians * 0.5),
            0, 0, degrees, true, sx, sy, sz);
    }

    static function assertHeapsMatrix(actual:h3d.Matrix,
            expected:TransformMatrix, message:String):Void {
        var values = [
            {actual: actual._11, expected: expected.m00},
            {actual: actual._12, expected: expected.m10},
            {actual: actual._13, expected: expected.m20},
            {actual: actual._21, expected: expected.m01},
            {actual: actual._22, expected: expected.m11},
            {actual: actual._23, expected: expected.m21},
            {actual: actual._31, expected: expected.m02},
            {actual: actual._32, expected: expected.m12},
            {actual: actual._33, expected: expected.m22},
            {actual: actual._41, expected: expected.m03},
            {actual: actual._42, expected: expected.m13},
            {actual: actual._43, expected: expected.m23}
        ];
        for (value in values) {
            if (!Math.isFinite(value.actual)
                    || Math.abs(value.actual - value.expected) > EPSILON) {
                throw '${message}: expected ${value.expected}, got ${value.actual}';
            }
        }
    }

    static function assertTrue(value:Bool, message:String):Void {
        if (!value) throw message;
    }
}
