package boltspark.ui;

/**
 * Shared, UI-neutral drag session used when an asset is dragged out of the
 * Asset Browser and onto a type-aware Inspector slot. The browser owns the
 * gesture and the capture; this session carries the payload, lights up every
 * slot that can accept it for the whole drag, and resolves the drop target.
 * A plain click never creates a session.
 */
class AssetDragSession {
    static var payload:Null<AssetDragPayload> = null;
    static var targets:Array<AssetDropTarget> = [];
    /** All live slots that accept the current payload, highlighted while dragging. */
    static var highlighted:Array<AssetDropTarget> = [];
    /**
     * Added to coordinates supplied by `update`/`drop`. A floating panel
     * reports client-local coordinates; drop targets live in the main editor
     * scene, so the float host installs the screen-space translation here.
     */
    public static var coordinateOffset:{x:Float, y:Float} = {x: 0, y: 0};

    public static function current():Null<AssetDragPayload> return payload;

    public static function begin(value:AssetDragPayload):Void {
        clearHighlights();
        prune();
        payload = value;
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] asset drag begin session type=${value.assetType}'
                + ' targets=${targets.length}');
        }
        // Show the user where this asset can go as soon as the drag starts.
        for (target in targets) {
            if (!target.isAlive() || target.assetType != value.assetType) continue;
            target.onHighlight(true);
            highlighted.push(target);
        }
    }

    public static function cancel():Void {
        clearHighlights();
        payload = null;
    }

    public static function add(target:AssetDropTarget):Void {
        prune();
        targets.push(target);
    }

    public static function remove(target:AssetDropTarget):Void {
        targets.remove(target);
        var index = highlighted.indexOf(target);
        if (index >= 0) {
            target.onHighlight(false);
            highlighted.splice(index, 1);
        }
    }

    /** Return the compatible slot under the cursor, if any. */
    public static function update(mouseX:Float, mouseY:Float):Null<AssetDropTarget> {
        if (payload == null) return null;
        prune();
        var x = mouseX + coordinateOffset.x;
        var y = mouseY + coordinateOffset.y;
        for (target in targets) {
            if (!target.isAlive() || target.assetType != payload.assetType) continue;
            var rect = target.rect();
            if (x >= rect.x && x < rect.x + rect.width
                    && y >= rect.y && y < rect.y + rect.height) {
                return target;
            }
        }
        return null;
    }

    /** Resolve and feed the drop, then tear the session down. */
    public static function drop(mouseX:Float, mouseY:Float):Bool {
        var target = update(mouseX, mouseY);
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] asset drop at=${Std.int(mouseX + coordinateOffset.x)}'
                + ',${Std.int(mouseY + coordinateOffset.y)}'
                + ' target=${target != null}');
        }
        if (target == null || payload == null) {
            cancel();
            return false;
        }
        var dropped = payload;
        clearHighlights();
        payload = null;
        target.onDrop(dropped);
        return true;
    }

    static function clearHighlights():Void {
        for (target in highlighted) target.onHighlight(false);
        highlighted.resize(0);
    }

    static function prune():Void {
        var alive:Array<AssetDropTarget> = [];
        for (target in targets) if (target.isAlive()) alive.push(target);
        targets = alive;
    }
}
