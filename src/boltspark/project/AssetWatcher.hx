package boltspark.project;

import haxe.io.Path;

/**
 * Detects external edits to project files and reports one debounced signal so
 * the Asset Browser can re-scan.
 *
 * The watcher takes a lightweight snapshot of the asset directory tree on a
 * timer and compares path/mtime/size signatures. A polling design is deliberate:
 * the libuv `hl.uv.Fs` watcher opens persistent native directory handles, and on
 * Windows those handles prevent the editor from renaming or deleting watched
 * folders — exactly the operations the Asset Browser performs. The probe suite
 * reproduced that failure (folder reparent reported OK but the OS rename was
 * refused). Polling touches no native handles, so asset operations stay safe.
 *
 * Build/VCS/dependency directories are skipped and the walk is capped, so a
 * large project cannot stall a frame. The host calls `update()` once per frame.
 */
class AssetWatcher {
    /** How often the tree is re-snapshotted. */
    static inline var POLL_INTERVAL_SECONDS:Float = 0.35;
    /** Upper bound on tracked paths, so huge trees cannot stall a frame. */
    static inline var MAX_ENTRIES:Int = 4096;
    /** Guard against symlink cycles or pathological nesting. */
    static inline var MAX_DEPTH:Int = 24;

    /** Directories that are never visited: build output, VCS, dependencies. */
    static final SKIP_NAMES:Array<String> = [
        ".git", ".hg", ".svn", ".vs", ".idea", "__pycache__",
        "bin", "obj", "release", "toolchain", "third_party",
        "tools", "node_modules"
    ];

    final onChange:Void->Void;
    var root:String = "";
    var snapshot:Map<String, String> = new Map();
    var hasSnapshot:Bool = false;
    var nextPollAt:Float = 0;

    public function new(onChange:Void->Void) {
        this.onChange = onChange;
    }

    /**
     * Absolute asset root to watch. Passing the current root is a no-op, so
     * this is safe to call from the frame loop and naturally follows project
     * open/Save As transitions without duplicating the scratch-root rules.
     */
    public function setRoot(path:String):Void {
        var next = (path == null || path.length == 0) ? "" : sys.FileSystem.absolutePath(path);
        if (next == root) return;
        root = next;
        hasSnapshot = false;
        snapshot = new Map();
        nextPollAt = haxe.Timer.stamp() + POLL_INTERVAL_SECONDS;
    }

    /** Clear all state. Safe to call repeatedly. */
    public function stop():Void {
        root = "";
        hasSnapshot = false;
        snapshot = new Map();
    }

    /**
     * Poll the tree once per interval and dispatch a single signal when a path
     * is added, removed, renamed, or modified. The first snapshot is the
     * baseline and never fires.
     */
    public function update():Void {
        if (root == "") return;
        var now = haxe.Timer.stamp();
        if (now < nextPollAt) return;
        nextPollAt = now + POLL_INTERVAL_SECONDS;

        var next = capture();
        if (!hasSnapshot) {
            snapshot = next;
            hasSnapshot = true;
            // One-time signal so probes can wait for the baseline before they
            // make an external change; without it a fast write can be folded
            // into the baseline and never produce a "changed" edge.
            Sys.println('[probe] watcher baseline established');
            return;
        }
        var changed = false;
        for (path => signature in next) {
            if (!snapshot.exists(path) || snapshot.get(path) != signature) {
                changed = true;
                break;
            }
        }
        if (!changed) {
            for (path in snapshot.keys()) {
                if (!next.exists(path)) {
                    changed = true;
                    break;
                }
            }
        }
        snapshot = next;
        if (changed) onChange();
    }

    function capture():Map<String, String> {
        var result = new Map<String, String>();
        if (root == "" || !sys.FileSystem.exists(root) || !sys.FileSystem.isDirectory(root)) {
            return result;
        }
        var count = { value: 0 };
        walk(root, result, 0, count);
        return result;
    }

    static function walk(dir:String, out:Map<String, String>, depth:Int,
            count:{ value:Int }):Void {
        if (depth > MAX_DEPTH || count.value >= MAX_ENTRIES) return;
        out.set("d:" + dir, "dir");
        count.value++;
        var entries:Array<String> = [];
        try {
            entries = sys.FileSystem.readDirectory(dir);
        } catch (e:Dynamic) {
            return;
        }
        for (name in entries) {
            if (count.value >= MAX_ENTRIES) break;
            if (name.charAt(0) == "." || SKIP_NAMES.indexOf(name) >= 0) continue;
            var child = Path.join([dir, name]);
            var isDir = false;
            try {
                isDir = sys.FileSystem.isDirectory(child);
            } catch (e:Dynamic) {}
            if (isDir) {
                walk(child, out, depth + 1, count);
            } else {
                try {
                    var stat = sys.FileSystem.stat(child);
                    out.set("f:" + child,
                        '${stat.mtime.getTime()}-${stat.size}');
                    count.value++;
                } catch (e:Dynamic) {}
            }
        }
    }
}
