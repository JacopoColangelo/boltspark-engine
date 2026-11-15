package boltspark.editor;

/** Built-in editor object kinds currently available from the hierarchy. */
enum abstract EditorObjectKind(String) from String to String {
    var Empty = "empty";
    var Cube = "cube";

    public static function require(value:String):EditorObjectKind {
        return switch (value) {
            case Empty: Empty;
            case Cube: Cube;
            default: throw 'Unsupported editor object kind: ${value}';
        };
    }
}
