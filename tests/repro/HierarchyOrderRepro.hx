import boltspark.ui.HierarchyEntry;
import boltspark.ui.HierarchyOrder;

/** Headless checks for the view-only scene hierarchy sort. */
class HierarchyOrderRepro {
    static function main():Void {
        testAuthoredOrder();
        testNameOrder();
        testTypeOrder();
        testModelOrderUntouched();
        Sys.println("[hierarchy-order] authored, name, and type ordering passed");
    }

    static function entries():Array<HierarchyEntry> {
        return [
            entry(1, "Zebra", -1, 0, "GameObject", true, 2),
            entry(3, "Beta", 1, 0, "Mesh3D"),
            entry(4, "Apple", 1, 1, "GameObject"),
            entry(2, "Alpha", -1, 1, "Mesh3D", true, 1),
            entry(5, "Gamma", 2, 0, "GameObject")
        ];
    }

    static function entry(id:Int, name:String, parentId:Int, siblingIndex:Int,
            typeName:String, hasChildren:Bool = false,
            childCount:Int = 0):HierarchyEntry {
        return new HierarchyEntry(id, name, "", parentId, 0, hasChildren,
            typeName == "Mesh3D", childCount, siblingIndex, typeName);
    }

    static function testAuthoredOrder():Void {
        assertIds(HierarchyOrder.order(entries(), HierarchyOrder.AUTHORED, true),
            [1, 3, 4, 2, 5], "authored order changed");
    }

    static function testNameOrder():Void {
        assertIds(HierarchyOrder.order(entries(), HierarchyOrder.NAME, true),
            [2, 5, 1, 4, 3], "ascending name order was incorrect");
        assertIds(HierarchyOrder.order(entries(), HierarchyOrder.NAME, false),
            [1, 3, 4, 2, 5], "descending name order was incorrect");
    }

    static function testTypeOrder():Void {
        assertIds(HierarchyOrder.order(entries(), HierarchyOrder.TYPE, true),
            [1, 4, 3, 2, 5], "ascending type order was incorrect");
        assertIds(HierarchyOrder.order(entries(), HierarchyOrder.TYPE, false),
            [2, 5, 1, 3, 4], "descending type order was incorrect");
    }

    static function testModelOrderUntouched():Void {
        var source = entries();
        var sorted = HierarchyOrder.order(source, HierarchyOrder.NAME, true);
        assertIds(source, [1, 3, 4, 2, 5], "sort mutated the stored entries");
        var authored:Map<Int, Int> = [];
        for (entry in source) authored.set(entry.id, entry.siblingIndex);
        for (entry in sorted) {
            if (authored.get(entry.id) != entry.siblingIndex) {
                throw 'sibling index was rewritten for ${entry.name}';
            }
        }
    }

    static function assertIds(actual:Array<HierarchyEntry>, expected:Array<Int>,
            message:String):Void {
        if (actual.length != expected.length) throw message;
        for (index in 0...actual.length) {
            if (actual[index].id != expected[index]) {
                throw '${message}: expected ${expected.join(",")}, got ${ids(actual).join(",")}';
            }
        }
    }

    static function ids(entries:Array<HierarchyEntry>):Array<Int> {
        return [for (entry in entries) entry.id];
    }
}
