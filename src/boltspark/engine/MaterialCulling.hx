package boltspark.engine;

/** Renderer-neutral face-culling mode. */
enum abstract MaterialCulling(String) from String to String {
    var Back = "back";
    var Front = "front";
    var None = "none";
    var Both = "both";
}
