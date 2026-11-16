package boltspark.engine.inspector;

/** UI-neutral property shapes understood by the editor Inspector. */
enum abstract ComponentPropertyKind(String) from String to String {
    var Vector3 = "vector3";
    var Text = "text";
    /** Object picker bound to a reusable asset reference (mesh, material, ...). */
    var Asset = "asset";
    /** Single scalar with a configured range (number or integer step). */
    var Number = "number";
    /** Integer scalar: displayed and committed without decimals. */
    var Integer = "integer";
    /** On/off toggle. */
    var Boolean = "boolean";
}
