package boltspark.editor;

/** Editor actions that can carry a keyboard binding. */
enum abstract EditorAction(Int) from Int to Int {
    var ToolMove = 0;
    var ToolRotate = 1;
    var ToolScale = 2;
    var DeleteSelection = 3;
    var SnapToGrid = 4;
    var HoldSnapOff = 5;
    var Undo = 6;
    var Redo = 7;
    var CopySelection = 8;
    var Paste = 9;
    var DuplicateSelection = 10;
    var RenameSelection = 11;
    var ACTION_COUNT = 12;
}
