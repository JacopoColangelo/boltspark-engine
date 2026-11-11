# Boltspark native foundation architecture — Windows 11 / DirectX 12

## 1. Decisions to lock now

### ADR-001 — No browser-based editor shell

**Decision:** BoltUI is rendered directly by Heaps. No Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML, or CSS application UI is permitted.

**Reason:** The editor is part of the engine process and must share the Heaps rendering/input lifecycle without a browser runtime or IPC boundary.

**Enforcement:** CI should scan source, project metadata, and dependency manifests for prohibited packages and runtime hooks. Any exception requires an explicit architecture decision; no agent may add one opportunistically.

### ADR-002 — Use `hxd.App` for the first native lifecycle

**Decision:** Start from `hxd.App`; do not write a custom native window loop before the standard Heaps path is proven.

**Reason:** `hxd.App` creates and owns the default `s2d` and `s3d` scenes and coordinates asset loading, initialization, update, rendering, and resize handling.

### ADR-003 — Windows 11 native graphics backend

**Decision:** The first Boltspark target is Windows 11 x64 using HashLink + Heaps `hldx` configured for DirectX 12.

**Build selection:** Both `-lib hldx` and `-D dx12` are mandatory in `compile.hxml`. Do not include `-lib hlsdl` or an implicit SDL/OpenGL/DirectX 11 fallback in this target. Heaps documents `-lib hldx -D dx12` as its Windows DirectX 12 configuration.

**Runtime requirement:** The HashLink runtime must provide both `directx.hdll` (native window/input/event services) and `dx12.hdll` (the Direct3D 12 rendering driver). The two modules are separate native targets in HashLink's DirectX build. The Haxe `hldx` binding package is distinct from both runtime modules.

**Agility SDK requirement:** This foundation uses the Agility-enabled DX12 runtime. The matching `D3D12Core.dll` and `d3d12SDKLayers.dll` must be placed in a `D3D12` directory beside the executable, and the package version must match `HL_DX12_AGILITY_VERSION` in the HashLink build. In the JIT development workflow, that executable is `hl.exe`.

**Reason:** A single known DX12 backend and pinned runtime set makes startup failures, rendering bugs, and agent builds deterministic. Do not silently select another backend if a DX12 component is missing.

### ADR-004 — Heaps 2D is the initial BoltUI renderer

**Decision:** Use `h2d.Scene`, `h2d.Graphics`, `h2d.Text`, `h2d.Interactive`, and other native H2D primitives as the first rendering/input layer.

**Reason:** Heaps renders the 3D scene and then the 2D scene in the standard app render path, making H2D a direct overlay path for editor UI.

### ADR-005 — No custom renderer until the vertical slice passes

**Decision:** Keep the default Heaps 3D renderer for the initial foundation. Add a renderer abstraction and custom passes only after startup, 2D overlay, 3D scene, input, resize, and smoke tests are stable.

**Reason:** A deferred renderer, custom viewport compositor, and UI framework at once would make backend failures difficult to isolate.

## 2. Runtime layers

```text
Boltspark Editor Process (Windows 11 x64)
└── Main (hxd.App)
    ├── HashLink VM
    │   ├── directx.hdll (native window/input/event services)
    │   └── dx12.hdll (Direct3D 12 rendering driver)
    ├── Heaps lifecycle and event routing
    ├── 3D scene (s3d)
    │   └── editor viewport content (meshes, cameras, lights)
    └── 2D scene (s2d)
        └── BoltUI root
            ├── Dock/layout model (future)
            ├── Widget state + stable IDs (future)
            ├── Input/focus/capture routing (future)
            └── H2D renderer (graphics, text, hit regions)
```

## 3. Suggested source layout after the first proof

```text
src/
  Main.hx
  boltspark/
    app/
      EditorApp.hx
      AppConfig.hx
    platform/
      NativeWindowInfo.hx
      PlatformCapabilities.hx
    ui/
      BoltUI.hx
      UiContext.hx
      UiInputState.hx
      UiStyle.hx
      layout/
        Rect.hx
        DockNode.hx
        SplitLayout.hx
      widgets/
        Button.hx
        Label.hx
        Panel.hx
      render/
        H2DRenderer.hx
        DrawCommand.hx
        TextCommand.hx
    editor/
      EditorState.hx
      SelectionState.hx
```

Do not create all of these modules before the native proof passes. Split them out when a concrete implementation needs them.

## 4. BoltUI design recommendation

Use a **hybrid immediate-mode API with retained rendering resources**:

- The editor describes the visible UI each frame through a compact API.
- Every interactive widget has a stable ID; state is keyed by that ID, not by object address.
- Layout emits rectangles and draw commands.
- Input is resolved against last-frame hit regions, with explicit pointer capture for drag operations and an explicit keyboard-focus owner.
- The H2D backend reuses/pools `h2d.Graphics`, `h2d.Text`, and hit regions. Do not create/destroy a large H2D object tree on every frame.
- The document/scene model is independent of the UI tree. UI controls dispatch editor commands; they do not own engine objects.

Proposed surface API (design target, not implemented in this starter):

```haxe
ui.beginFrame(input);
ui.beginPanel("Hierarchy", panelRect);
if (ui.button("create-empty", "Create Empty")) editor.createEmptyEntity();
ui.label("Scene");
ui.endPanel();
ui.endFrame();
```

The API should not expose H2D implementation classes to editor tools. Keep the rendering backend replaceable even if H2D remains the long-term backend.

## 5. Rendering order and viewport strategy

For the first slice, render the full 3D scene through `s3d` and draw editor chrome over it through `s2d`.

For a real editor layout, the 3D viewport must become a bounded region rather than a fullscreen background. Do not hack the viewport by layering opaque panels forever. Prototype one of these Heaps-compatible approaches after the foundation passes:

1. A 3D scene output target rendered to a texture, then displayed in a clipped H2D viewport region.
2. A supported sub-scene/scene-position path if it satisfies clipping, picking, resize, and DPI requirements.

The choice must be tested for GPU resource lifecycle, picking-coordinate conversion, high-DPI behavior, and render-target resize. Record findings before implementing docking.

## 6. Input model

Centralize input translation into engine-independent UI events:

- pointer move/down/up and wheel;
- keyboard down/up and text input;
- focus gained/lost;
- window resize and close;
- drag/drop later.

Keep these distinctions explicit:

- **hover:** current pointer over a hit region;
- **capture:** a widget continues receiving pointer movement/up after pointer leaves its bounds;
- **focus:** a widget receives keyboard/text input;
- **activation:** click/submit/shortcut action.

Use H2D `Interactive` for the first button proof. Before implementing docking, add central pointer capture and keyboard focus handling; splitter drags and text fields depend on them.

## 7. Performance and resilience rules

- No per-frame allocation of a complete display tree.
- Batch static geometry where practical; minimize texture switches.
- Separate layout invalidation from drawing; resize or content changes should not force unrelated panels to rebuild.
- Never keep stale GPU resources across device loss/reset; add a device-loss/recreate test before custom render targets.
- Do not hardcode physical pixels as the long-term unit. Introduce logical UI units and a DPI scale after the first window proof.
- Keep rendering state and editor domain state separate.
- No agent may alter the native backend or add a new UI library without an ADR and passing the acceptance suite.
