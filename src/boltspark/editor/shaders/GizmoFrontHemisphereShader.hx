package boltspark.editor.shaders;

/**
 * Hides the rear half of a rotation ring as though the ring were wrapped
 * around an invisible sphere centered on the transform gizmo.
 */
class GizmoFrontHemisphereShader extends hxsl.Shader {
	static var SRC = {
		@:import h3d.shader.BaseMesh;

		@param var gizmoCenter:Vec3;
		@param var ringAxis:Vec3;
		@param var visibilityPadding:Float;

		function fragment() {
			var offset = transformedPosition - gizmoCenter;
			// Remove the torus tube's axial offset so every cross-section is
			// classified as one ring segment instead of being sliced in half.
			var radial = offset - ringAxis * dot(offset, ringAxis);
			var viewDirection = normalize(camera.position - gizmoCenter);
			if (dot(radial, viewDirection) < -visibilityPadding) discard;
		}
	};

	public function new() {
		super();
		gizmoCenter.set(0, 0, 0);
		ringAxis.set(0, 1, 0);
		visibilityPadding = 0;
	}
}
