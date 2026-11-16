package boltspark.project;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Atomic UTF-8 document writes with one recoverable previous-version backup. */
class DocumentStore {
    public static function saveProject(path:String, project:ProjectDocument):Void {
        saveAtomic(path, ProjectCodec.encode(project));
    }

    public static function loadProject(path:String):ProjectDocument {
        return ProjectCodec.decode(read(path));
    }

    public static function saveScene(path:String, scene:SceneDocument):Void {
        saveAtomic(path, SceneCodec.encode(scene));
    }

    public static function loadScene(path:String):SceneDocument {
        return SceneCodec.decode(read(path));
    }

    public static function saveAtomic(path:String, contents:String):Void {
        var directory = Path.directory(path);
        if (directory != null && directory != "" && !FileSystem.exists(directory)) {
            createDirectories(directory);
        }
        var temporary = path + ".tmp";
        var backup = path + ".bak";
        File.saveContent(temporary, contents);
        var hadOriginal = FileSystem.exists(path);
        try {
            if (hadOriginal) {
                if (FileSystem.exists(backup)) FileSystem.deleteFile(backup);
                FileSystem.rename(path, backup);
            }
            FileSystem.rename(temporary, path);
        } catch (error:Dynamic) {
            if (FileSystem.exists(temporary)) FileSystem.deleteFile(temporary);
            if (hadOriginal && !FileSystem.exists(path) && FileSystem.exists(backup)) {
                FileSystem.rename(backup, path);
            }
            throw 'Atomic save failed for ${path}: ${Std.string(error)}';
        }
    }

    static function read(path:String):String {
        if (!FileSystem.exists(path)) throw 'Document does not exist: ${path}';
        try {
            var contents = File.getContent(path);
            // Windows editors commonly save JSON with a UTF-8 BOM; the strict
            // codecs reject it at position 0, so strip it before decoding.
            if (contents.length > 0 && contents.charCodeAt(0) == 0xFEFF) {
                contents = contents.substr(1);
            }
            return contents;
        } catch (error:Dynamic) {
            throw 'Could not read ${path}: ${Std.string(error)}';
        }
    }

    static function createDirectories(path:String):Void {
        if (path == null || path == "" || FileSystem.exists(path)) return;
        var parent = Path.directory(path);
        if (parent != path) createDirectories(parent);
        FileSystem.createDirectory(path);
    }
}
