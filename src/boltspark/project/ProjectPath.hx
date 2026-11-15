package boltspark.project;

/** Cross-platform serialized path rules: relative, slash-separated, no escape. */
class ProjectPath {
    public static function normalizeRelative(value:String):String {
        if (value == null) throw "Project path cannot be null";
        var normalized = StringTools.replace(StringTools.trim(value), "\\", "/");
        while (normalized.indexOf("//") >= 0) {
            normalized = StringTools.replace(normalized, "//", "/");
        }
        if (normalized.length == 0) throw "Project path cannot be empty";
        if (StringTools.startsWith(normalized, "/") || normalized.indexOf(":") >= 0) {
            throw 'Project path must be relative: ${value}';
        }
        var clean:Array<String> = [];
        for (part in normalized.split("/")) {
            if (part == "" || part == ".") continue;
            if (part == "..") throw 'Project path cannot escape its project: ${value}';
            clean.push(part);
        }
        if (clean.length == 0) throw "Project path cannot resolve to the project root";
        return clean.join("/");
    }
}
