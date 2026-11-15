package boltspark.engine.inspector;

/** UI-neutral property shapes understood by the editor Inspector. */
enum abstract ComponentPropertyKind(String) from String to String {
    var Vector3 = "vector3";
    var Text = "text";
}
