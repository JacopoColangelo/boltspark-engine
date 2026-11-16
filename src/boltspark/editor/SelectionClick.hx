package boltspark.editor;

/**
 * How a viewport click changes the selection. Modifier semantics mirror the
 * hierarchy rows so the two selection surfaces behave the same way:
 *   - Replace: a plain click selects only the clicked object,
 *   - Toggle:  Ctrl+click adds the object or removes it when already selected,
 *   - Add:     Shift+click adds the object without dropping the rest.
 *
 * Kept renderer-independent and allocation-light so it can be exercised by
 * headless repros and shared by any future selection source.
 */
enum abstract SelectionClickMode(Int) from Int to Int {
    var Replace:SelectionClickMode = 0;
    var Toggle:SelectionClickMode = 1;
    var Add:SelectionClickMode = 2;
}

typedef SelectionClickResult = {
    /** New selection, hierarchy/registration order preserved on additive edits. */
    var ids:Array<Int>;
    /** New primary ("last clicked") object, or -1 for an empty selection. */
    var primary:Int;
};

class SelectionClick {
    /**
     * Apply a click on `clickedId` to the current selection. A negative id
     * means empty space and always clears the selection.
     */
    public static function apply(currentIds:Array<Int>, currentPrimary:Int,
            clickedId:Int, mode:SelectionClickMode):SelectionClickResult {
        if (clickedId < 0) return {ids: [], primary: -1};
        var ids = currentIds == null ? [] : currentIds.copy();
        return switch (mode) {
            case Toggle:
                var index = ids.indexOf(clickedId);
                if (index >= 0) {
                    ids.splice(index, 1);
                    var primary = ids.indexOf(currentPrimary) >= 0
                        ? currentPrimary
                        : (ids.length == 0 ? -1 : ids[ids.length - 1]);
                    {ids: ids, primary: primary};
                } else {
                    ids.push(clickedId);
                    {ids: ids, primary: clickedId};
                }
            case Add:
                if (ids.indexOf(clickedId) < 0) ids.push(clickedId);
                {ids: ids, primary: clickedId};
            default:
                {ids: [clickedId], primary: clickedId};
        };
    }
}
