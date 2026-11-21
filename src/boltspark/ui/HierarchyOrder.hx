package boltspark.ui;

/** View-only ordering for scene hierarchy rows. Never mutates the scene model. */
class HierarchyOrder {
    public static inline var AUTHORED:Int = 0;
    public static inline var NAME:Int = 1;
    public static inline var TYPE:Int = 2;

    /**
     * Sort siblings within each parent and return a pre-order traversal of the
     * resulting tree. `HierarchyEntry.siblingIndex` stays at its authored value
     * so hierarchy drag/drop still targets model positions.
     */
    public static function order(entries:Array<HierarchyEntry>, key:Int,
            ascending:Bool):Array<HierarchyEntry> {
        if (key == AUTHORED) return entries.copy();

        var grouped:Map<Int, Array<HierarchyEntry>> = [];
        for (entry in entries) {
            var siblings = grouped.get(entry.parentId);
            if (siblings == null) {
                siblings = [];
                grouped.set(entry.parentId, siblings);
            }
            siblings.push(entry);
        }

        var direction = ascending ? 1 : -1;
        for (siblings in grouped) {
            siblings.sort(function(a, b) {
                var comparison = key == NAME
                    ? compareText(a.name, b.name)
                    : compareText(a.typeName, b.typeName);
                if (comparison == 0) comparison = a.siblingIndex - b.siblingIndex;
                return comparison * direction;
            });
        }

        var ordered:Array<HierarchyEntry> = [];
        var stack:Array<HierarchyEntry> = [];
        var roots = grouped.get(-1);
        if (roots != null) {
            var index = roots.length - 1;
            while (index >= 0) stack.push(roots[index--]);
        }
        while (stack.length > 0) {
            var entry = stack.pop();
            ordered.push(entry);
            var children = grouped.get(entry.id);
            if (children != null) {
                var index = children.length - 1;
                while (index >= 0) stack.push(children[index--]);
            }
        }
        return ordered;
    }

    static inline function compareText(a:String, b:String):Int {
        return a == b ? 0 : (a < b ? -1 : 1);
    }
}
