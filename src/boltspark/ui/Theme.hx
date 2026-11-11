package boltspark.ui;

/**
 * BoltUI theme tokens.
 *
 * All colors are sRGB hex values (0xRRGGBB) and all sizes are logical
 * pixels at 1x scale. Gate 4 will extend this with DPI scaling and
 * per-theme overrides; M0 keeps a single fixed editor theme.
 */
class Theme {
    // Layout metrics.
    public static inline var TOP_BAR_HEIGHT:Int = 48;
    public static inline var STATUS_BAR_HEIGHT:Int = 24;
    public static inline var CONSOLE_HEIGHT:Int = 148;
    public static inline var LEFT_PANEL_WIDTH:Int = 224;
    public static inline var RIGHT_PANEL_WIDTH:Int = 280;
    public static inline var SPLITTER_SIZE:Int = 8;
    public static inline var SPLITTER_VISIBLE_WIDTH:Int = 2;
    public static inline var SPLITTER_HOVER:Int = 0x58718D;
    public static inline var MIN_LEFT_PANEL_WIDTH:Int = 216;
    public static inline var MIN_CENTER_PANEL_WIDTH:Int = 240;
    public static inline var SPACING:Int = 16;
    public static inline var BUTTON_WIDTH:Int = 184;
    public static inline var BUTTON_HEIGHT:Int = 34;
    public static inline var CONTROL_HEIGHT:Int = 30;

    // Palette.
    public static inline var TOP_BAR:Int = 0x202630;
    public static inline var PANEL:Int = 0x1D232D;
    public static inline var PANEL_EDGE:Int = 0x303A48;
    public static inline var CONSOLE_BG:Int = 0x12151B;
    public static inline var FIELD_BG:Int = 0x151A22;
    public static inline var FIELD_FOCUS:Int = 0x202B39;
    public static inline var ACCENT:Int = 0xD97732;
    public static inline var TEXT:Int = 0xE8EDF3;
    public static inline var MUTED:Int = 0x9AA7B7;
    public static inline var BUTTON:Int = 0x34465B;
    public static inline var BUTTON_HOVER:Int = 0x3F566F;
    public static inline var BUTTON_ACTIVE:Int = 0x2C3B4D;
    public static inline var SWATCH_EDGE:Int = 0x0B0E13;
    public static inline var SWATCH_SELECTED:Int = 0xFFFFFF;

    // Editor cube sample colors (also used by the inspector swatches).
    public static inline var CUBE_ORANGE:Int = 0xE58A3A;
    public static inline var CUBE_STEEL:Int = 0x7FA6C9;
    public static inline var CUBE_MOSS:Int = 0x7FB069;
    public static inline var CUBE_VIOLET:Int = 0xA78BFA;
}
