# Boltspark Engine — Master Development Plan

**Revision:** 3.0  
**Status:** Proposed implementation plan; native DX12 and BoltUI feasibility gates must pass before delivery estimates are committed.  
**Primary development target:** Windows 11 x64.  
**Graphics backend:** Direct3D 12 through Heaps + HashLink (`hldx` with `-D dx12`).  
**Editor UI:** BoltUI, rendered directly by Heaps (`h2d`).  
**Non-negotiable platform policy:** No Electron, NW.js, CEF, Chromium shell, Tauri, Wails, WebView, embedded browser, DOM, HTML, or CSS-based editor UI.

---

## Executive Summary

Boltspark is a native, single-process game engine and editor built with **Haxe**, **Heaps.io**, and **HashLink**. Its first supported development platform is **Windows 11 x64**, with **Direct3D 12** as the selected graphics backend. The desktop editor, its tools, and its UI are rendered directly by Heaps; the editor does not host a browser runtime or depend on a browser-based desktop shell.

The first engineering objective is not to build every engine feature. It is to prove and stabilize the foundation on which every later feature depends:

1. A reproducible Windows 11 x64 toolchain.
2. A working HashLink + Heaps DirectX 12 application.
3. A native Heaps application lifecycle using `hxd.App`.
4. A small but real BoltUI system rendered with Heaps 2D primitives.
5. A working 3D scene and native UI in the same process.
6. Reliable input, resizing, focus, shutdown, logging, and diagnostics.
7. A repeatable test and build process that autonomous agents can use without inventing their own platform setup.

Only after this proof passes should the project grow into a complete editor, asset pipeline, scene system, PBR renderer, physics integration, or advanced visual effects.

Boltspark may use **HIDE (Heaps IDE)** as a reference and as a source of portable data models, serialization, algorithms, and editor-domain logic. HIDE's HTML/DOM presentation layer and browser-oriented desktop hosting are excluded. Every candidate HIDE subsystem must be audited before reuse; no module is assumed to be portable simply because it is written in Haxe.

This plan uses milestone exit gates instead of promising a fixed 20-sprint delivery schedule. Time estimates become meaningful only after the native DX12 foundation has been built, measured, and integrated on the actual Windows 11 development machine.

---

# 1. Product Principles and Non-Negotiable Constraints

## 1.1 Product principles

1. **Native first:** The Windows desktop editor is a native application. Its UI is rendered by Heaps and does not require a browser process, WebView, or HTML runtime.
2. **DirectX 12 first:** The first Windows graphics target is the Heaps/HashLink DirectX 12 backend. Missing DX12 dependencies are a startup/build failure, not a reason to silently fall back to another renderer.
3. **One process, modular architecture:** The editor, engine runtime, asset pipeline, and tools may share a process and repository, but must retain explicit module boundaries. “Monolithic” must not mean tightly coupled.
4. **Use Heaps before replacing Heaps:** Prefer Heaps' scene, resource, shader, and rendering abstractions. Add custom renderer code only to solve a demonstrated requirement that Heaps cannot meet adequately.
5. **BoltUI before editor breadth:** Establish the UI rendering, layout, input, focus, and viewport-composition foundations before implementing large editor tools.
6. **Vertical-slice delivery:** Each milestone must produce an end-to-end, runnable capability rather than disconnected classes.
7. **Data-oriented project model:** Scene, prefab, material, animation, and effect data must be serializable, inspectable, versioned, and usable by both editor and runtime.
8. **Evidence over claims:** Performance, compatibility, memory, and platform support must be demonstrated on recorded hardware, OS, driver, toolchain, and build configurations.
9. **AI-assisted implementation with accountable review:** AI agents may implement bounded tasks, but an accountable project owner/reviewer must approve architecture changes, licensing decisions, security assumptions, dependency changes, and release acceptance.

## 1.2 Native-only editor policy

The following are prohibited in the Boltspark desktop editor and its required UI dependencies:

- Electron and NW.js.
- Chromium Embedded Framework (CEF) or a bundled Chromium process.
- Tauri, Wails, or another shell that hosts the editor UI in a WebView.
- WebView2, embedded browsers, browser controls, or browser-hosted panels.
- HTML, CSS, DOM, or JavaScript-based editor surfaces.
- Node.js-based editor frontends or hidden browser processes used for docking, inspectors, asset browsers, documentation, or other editor features.

The following are allowed:

- Heaps `h2d` scenes, graphics, text, interactive objects, textures, and shader-based UI drawing.
- A custom BoltUI immediate-mode or hybrid UI toolkit rendered through Heaps.
- Native Windows APIs and native HashLink modules for window integration, clipboard, file dialogs, drag-and-drop, and OS services where Heaps does not supply the required functionality.
- External command-line tools for asset conversion, source control, packaging, or documentation, provided they do not host the editor UI.

**Enforcement:** CI and release checks must inspect dependency manifests, build files, output directories, and process trees for prohibited editor technologies. The editor must start and operate on a clean Windows 11 installation without Electron/NW.js/CEF/WebView/Node browser-shell dependencies.

A future web export for *games* may be evaluated separately. It must never become a method of hosting the desktop editor.

## 1.3 Initial product boundary

The first usable product slice should prioritize:

- A native Windows 11 editor using the DX12 backend.
- Project creation, opening, saving, and validation.
- Asset import and an asset registry.
- Scene hierarchy, inspector, viewport, selection, and transform gizmos.
- Meshes, cameras, materials, lights, and baseline shadows.
- Play/stop mode with a runtime that is separated from editor-only code.
- A reproducible Windows game build and launch workflow.

Advanced global illumination, volumetric lighting, large-world streaming, terrain sculpting, deep animation tooling, and extensive plugin ecosystems are later capabilities. They are not prerequisites for proving the foundation.

---

# 2. Technology Strategy and Windows 11 / DirectX 12 Baseline

## 2.1 Initial technology decisions

| Area | Initial direction | Proof or qualification required |
|---|---|---|
| OS | Windows 11 x64 | Record edition/build and test on a clean install or clean VM where practical |
| Language | Haxe 4.3.x; pin exact compiler | Current stable baseline and compiler version recorded in the toolchain lock |
| Engine framework | Heaps (`h2d`, `h3d`, `hxd`, `hxsl`) | Pin exact release/tag/commit and compile the DX12 vertical slice |
| Native runtime | HashLink 1.16 x64 as the initial stable baseline | Confirm the runtime build contains compatible DirectX modules and run real GPU tests |
| Graphics | Direct3D 12 through Heaps `hldx` | `-lib hldx` and `-D dx12` must both be present in the Windows target profile |
| Editor UI | BoltUI rendered by Heaps `h2d` | Prove drawing, text, input, layout, clipping, DPI, and viewport composition without a browser |
| 3D physics | Evaluate Jolt first behind a Boltspark abstraction | Verify ABI, memory ownership, callbacks, threading, deployment, and license |
| 2D physics | Evaluate Box2D only if the 2D product slice requires a separate backend | Avoid maintaining two physics integrations prematurely |
| Audio | Start with the Heaps-supported path | Verify formats, streaming, spatial audio, latency, and packaging on Windows |
| Data | Versioned Boltspark project/scene formats; selectively adapt HIDE formats | Fixture corpus, schema migrations, round-trip tests, and licensing review |
| Tests | `utest` plus integration, DX12 smoke, visual regression, and performance tests | CI must reproduce the same checks from a clean checkout |

## 2.2 Heaps and HashLink DX12 selection

The Windows DX12 HXML profile must select the DirectX library and the DX12 define. The official Heaps HashLink documentation describes `-lib hldx` for DirectX and `-D dx12` as the optional DirectX 12 selection.

Initial `compile.hxml` profile:

```hxml
-cp src
-lib heaps
-lib format
-lib hldx
-D dx12
-D windowSize=1440x900
-debug
-hl bin/boltspark.hl
-main Main
```

Rules:

- `-lib hldx` is required for the Heaps DirectX backend.
- `-D dx12` is required for the selected Direct3D 12 mode.
- Do not add `-lib hlsdl` to the Windows DX12 editor profile.
- Do not silently select SDL/OpenGL or DirectX 11 if DX12 initialization fails.
- Keep separate HXML profiles for editor development, automated checks, and release builds. Do not mix defines and output paths informally.
- Record all compiler/library versions and native module hashes in `docs/TOOLCHAIN_VERSIONS.md`.

The initial development output is HashLink bytecode (`.hl`) executed by the HashLink VM. HashLink/C output and a standalone native executable are separate release engineering tasks and must not be described as already available merely because Haxe produced `.hl` bytecode.

## 2.3 HashLink DirectX native modules

The HashLink DirectX source builds distinct native modules:

- **`directx.hdll`:** the Windows DirectX platform/window module. Its native build includes window-related code and links Windows graphics/input system libraries, including D3D11 and DXGI components.
- **`dx12.hdll`:** the Direct3D 12 rendering driver. Its native build links the D3D12, DXGI, and DXCompiler libraries.

Both modules must be x64 and compatible with the same HashLink VM/runtime build. The Haxe `hldx` Haxelib package provides Haxe-side bindings; it is not a replacement for the native `.hdll` runtime modules. The fact that `directx.hdll` links some D3D11 system libraries in its platform layer does not mean Boltspark has selected the D3D11 renderer: the selected Heaps rendering path is Direct3D 12 through `-D dx12` and `dx12.hdll`.

The environment check must:

1. Locate `hl.exe` and record its version.
2. Locate `directx.hdll` and `dx12.hdll` using the actual HashLink loader search rules.
3. Record the exact paths and file hashes.
4. Verify x64 architecture and compatible runtime versions.
5. Fail with a useful error if either module is absent.
6. Run the native DX12 smoke test; file presence alone is not proof that the driver loads or creates a device.

Do not copy random `.hdll` files from unrelated HashLink releases into the project. Treat the VM and native modules as one tested toolchain set.

## 2.4 DirectX 12 Agility SDK policy

The Agility SDK is **not automatically mandatory for every DirectX 12 build**. It is required when Boltspark chooses a HashLink build configuration that is built for the Agility SDK. This distinction must remain explicit in setup documentation.

Two supported configuration tracks should be evaluated during M0:

**Track A — Standard HashLink DX12 runtime (preferred first proof if it meets feature needs):**

- Build/use the official x64 HashLink DX12 runtime configuration without opting into the Agility SDK.
- Verify DX12 device creation, swap-chain presentation, rendering, resize, and validation on the target GPU/driver.
- Avoid adding Agility SDK deployment steps until a feature or compatibility requirement justifies them.

**Track B — HashLink DX12 Agility runtime (opt-in):**

- Build/use a HashLink configuration that explicitly enables its DX12 Agility SDK path.
- The Agility SDK package version must exactly match `HL_DX12_AGILITY_VERSION` used when building HashLink.
- HashLink's DirectX setup notes specify a `D3D12` directory beside the application executable containing `D3D12Core.dll` and `d3d12SDKLayers.dll`.
- During JIT development, the relevant executable is normally `hl.exe`; validate the folder placement with the actual run setup.
- Do not guess the SDK version, mix packages, or assume that a newer SDK is automatically compatible with the HashLink binary.

**Optional Agility-build integrations:** HashLink 1.16's DirectX README documents that its default `ReleaseDX12Agility` / `ReleaseAll` configuration enables both Nsight Aftermath GPU crash diagnostics and NVIDIA Streamline integration (used by `hlheaps` for DLSS). Those integrations introduce their own SDK and runtime DLL requirements. The same README documents building the `dx12` project with the `Release` configuration instead of `ReleaseAll` to omit those optional integrations and remove their extra dependencies.

For the first Boltspark DX12 proof, prefer the simplest compatible runtime configuration. Do not enable Aftermath or Streamline merely because they are available. Add them only through a deliberate decision, with the required SDKs, DLLs, license review, and tests. DLSS/Streamline is not a prerequisite for DX12 rendering.

For a Boltspark packaged executable, revalidate the final app-local folder structure and all runtime exports/loader behavior. HashLink's current instructions show the `D3D12` folder beside `hl.exe` for the JIT workflow. Do not assume that a development folder adjacent to `hl.exe` is automatically correct for the final standalone executable.

## 2.5 Provisional reproducible toolchain

Start with a known, recorded baseline rather than floating versions:

| Component | Provisional baseline | Locking instruction |
|---|---|---|
| Windows | Windows 11 x64 | Record edition, build, and installed updates |
| Haxe | 4.3.7 stable | Pin exact version; do not use preview/nightly for the foundation gate |
| Heaps | Existing scaffold uses 2.1.0 Haxelib package | Upstream Heaps 2.1.1 has a release; verify the exact package/source available to the project, then pin one source and revision. Do not mix Haxelib and Git checkouts implicitly |
| HashLink | 1.16 x64 stable baseline | Use the same release/commit for `hl.exe`, `directx.hdll`, and `dx12.hdll` |
| `hldx` | Matching Haxe binding package | Record exact Haxelib version/commit and verify API compatibility with the selected HashLink runtime |
| `format` | Exact Haxelib version recorded by lock file | Do not install “latest” in CI |
| Windows SDK / MSVC | Windows 11 SDK + supported Visual Studio C++ toolchain | Record exact component versions if building HashLink modules from source |
| Agility SDK | Not selected by default | If Track B is selected, record the matching package version and `HL_DX12_AGILITY_VERSION` |

The table is a starting point, not a claim that every combination has already been compiled together. The M0 gate must establish the final compatible set and replace provisional values with actual tested versions and file hashes.

## 2.6 Native build environment

If the required HashLink DX12 modules are not provided by a compatible official x64 runtime package, build HashLink from its official source using the documented Windows toolchain. The build environment should include:

- Windows 11 x64.
- Visual Studio 2022 Build Tools or a compatible supported Visual Studio toolchain.
- Desktop C++ workload and Windows SDK.
- CMake and the build tooling required by the HashLink source revision.
- The exact HashLink source tag/commit used for the VM and both native modules.
- The matching DirectX SDK/system libraries and, only if selected, Agility SDK and Nsight Aftermath dependencies.

Create a PowerShell setup/check/build/run path. Scripts must fail early and explain which dependency or version check failed. Do not silently download changing “latest” dependencies inside an agent task.

## 2.7 Development and release profiles

- **Editor development:** Haxe -> HashLink bytecode -> HashLink VM/JIT. This is the first working path.
- **CI compile:** same pinned HXML profile, with deterministic outputs and test execution.
- **Release candidate:** evaluate HashLink/C and native linking after the editor foundation and required Heaps/native modules are proven. Keep HLC generation and native C linking as separate steps.
- **Game runtime:** build without BoltUI/editor-only modules. The editor and exported game must share engine/runtime code only through deliberate module boundaries.

---

# 3. Native Application and BoltUI Architecture

## 3.1 Use the Heaps application lifecycle first

Start from **`hxd.App`**. It provides the normal Heaps application structure, including the rendering engine, default 2D and 3D scenes, scene event collection, initialization, update, rendering, and resize hooks.

The foundation should use these built-in lifecycle hooks rather than creating a custom native window loop before there is a demonstrated need.

Initial application responsibilities:

- `Main` selects and starts the application.
- `EditorApp` extends or composes `hxd.App` and owns editor-level lifecycle decisions.
- `s3d` hosts the initial 3D proof scene.
- `s2d` hosts the BoltUI root and editor chrome.
- `sevents`/Heaps event routing provides the initial native scene input path.
- `onResize` invalidates window-sized layout and render resources.
- `update` coordinates UI input/state, editor state, and scene updates.

Do not bypass Heaps' standard lifecycle for the first proof. Custom windowing or event loops require an architecture decision and a measured reason.

## 3.2 Runtime architecture

```text
Boltspark Editor Process — Windows 11 x64
└── Main
    └── EditorApp : hxd.App
        ├── HashLink VM/JIT
        │   ├── directx.hdll  (Windows DirectX platform/window services)
        │   └── dx12.hdll     (Direct3D 12 renderer)
        ├── Heaps Engine
        │   ├── h3d / s3d    (3D scene and editor viewport content)
        │   ├── h2d / s2d    (BoltUI presentation)
        │   └── hxd          (application lifecycle, resources, input/events)
        ├── Boltspark Core
        │   ├── project and asset model
        │   ├── scene and component model
        │   └── command/undo system
        └── BoltUI
            ├── UI context and stable widget IDs
            ├── layout and docking model
            ├── input routing, focus, and pointer capture
            ├── draw-command generation
            └── Heaps H2D renderer
```

The `directx.hdll` and `dx12.hdll` roles are distinct. The first supports the DirectX platform/window layer; the second provides the Direct3D 12 renderer. The exact native runtime search paths and module versions must be verified on the target machine.

## 3.3 BoltUI design goals

BoltUI is a native editor UI framework, not a wrapper around an existing web UI toolkit. It should be built on Heaps 2D drawing and input facilities, with a public API independent of its internal renderer.

**Recommended approach: hybrid immediate-mode UI with retained rendering resources.**

- Editor code describes visible controls and panels each frame.
- Interactive controls have stable IDs; state is keyed by ID rather than object address or allocation order.
- Widget state that must persist (text, selection, expanded nodes, drag state, scroll position) is held in explicit state stores.
- Layout produces logical rectangles, clipping regions, and draw commands.
- Input is routed through a central UI input layer.
- H2D graphics, text, and hit-test resources are reused or pooled; the framework must not allocate and discard an entire H2D object tree every frame.
- UI widgets issue editor commands; they do not own or mutate engine data models directly.
- The scene/project model remains independent of the UI hierarchy so UI replacement or layout changes cannot corrupt game data.

Proposed API direction (illustrative, not a committed public API):

```haxe
ui.beginFrame(input);
ui.beginPanel("Hierarchy", hierarchyRect);
if (ui.button("hierarchy.create-empty", "Create Empty")) {
    editor.commands.execute(new CreateEntityCommand());
}
ui.label("Scene");
ui.endPanel();
ui.endFrame();
```

Do not expose H2D implementation types to every editor tool. Keep them behind the BoltUI rendering backend.

## 3.4 BoltUI subsystems and implementation order

### A. UI context and frame lifecycle

- `beginFrame` / `endFrame`.
- Stable widget ID generation and ID scopes.
- Explicit style/theme context.
- Input snapshot for current frame.
- Persistent state storage for widgets.
- Diagnostics for duplicate IDs, invalid layout, and unbalanced UI scopes.

### B. Geometry and layout

- Rectangles, constraints, padding, spacing, alignment, and clipping.
- Start with deterministic row/column/stack layout.
- Add intrinsic measurement and layout invalidation after the simple model works.
- Use logical UI coordinates, with a single DPI scale conversion layer.
- Keep layout calculations independent from H2D drawing.

### C. Input and interaction

Centralize and normalize:

- Pointer move, down, up, and wheel.
- Keyboard down/up and text input.
- Focus gained/lost and window activation changes.
- Window resize and close.
- Drag/drop later, after basic pointer capture works.

Keep these concepts separate:

- **Hover:** pointer is currently over a hit region.
- **Capture:** a widget continues receiving pointer events after the pointer leaves its bounds.
- **Focus:** a widget receives keyboard and text input.
- **Activation:** a click, submit, or shortcut invokes an action.

Use Heaps interactive primitives for the first clickable proof, but centralize focus and capture before implementing docking, splitters, text editing, and drag operations.

### D. Initial widget set

Build only what the first editor shell requires:

- Label and icon/image.
- Button and toggle.
- Checkbox.
- Single-line text field (after keyboard focus/text input is reliable).
- Scrollable container/list.
- Panel, separator, splitter.
- Basic property row and numeric field.
- Tab header.

Do not build a full widget catalogue before the UI is used by a real editor workflow.

### E. Docking and workspace layout

Docking comes after stable panels, pointer capture, layout constraints, and workspace persistence. Implement:

- Split tree with horizontal/vertical nodes.
- Tabbed panel stacks.
- Drag/reorder and dock-target previews.
- Minimum panel sizes and collapse/restore.
- Workspace save/load with schema versioning.

Do not make docking a prerequisite for the first native window/3D/UI proof.

## 3.5 3D viewport composition

A real editor needs a bounded 3D viewport that can share the window with 2D panels. The first foundation can render a full 3D scene behind simple editor chrome, but the editor must not grow around that temporary layout.

During M1/M2, prototype and compare Heaps-compatible paths:

1. Render the 3D scene to a render target/texture, then display it inside a clipped H2D viewport region.
2. Use a supported Heaps scene/viewport arrangement if it provides correct clipping, sizing, picking, and input transformation.

The selected path must be verified for:

- DX12 render-target creation and resize.
- Resource release/recreation when viewport dimensions change.
- Correct coordinate conversion between window, viewport, render target, and mouse picking.
- Correct camera aspect ratio.
- DPI scaling and high-resolution displays.
- Scissor/clipping behavior for UI overlays.
- GPU resource lifetime across panel resize, viewport close, and editor shutdown.

Do not assume that a simple full-screen scene layered under opaque panels is a sufficient long-term viewport architecture.

## 3.6 Suggested source layout

Create only the folders required for the current milestone. A likely structure after M1/M2:

```text
src/
  Main.hx
  boltspark/
    app/
      EditorApp.hx
      AppConfig.hx
    platform/
      WindowsRuntimeCheck.hx
      NativeDialogs.hx
      PlatformCapabilities.hx
    core/
      logging/
      commands/
      ids/
      math/
    project/
      Project.hx
      ProjectSerializer.hx
      AssetRegistry.hx
    scene/
      Scene.hx
      Node3D.hx
      Component.hx
      Transform.hx
    render/
      RenderConfig.hx
      ViewportTarget.hx
    ui/
      BoltUI.hx
      UiContext.hx
      UiInputState.hx
      UiStyle.hx
      layout/
      widgets/
      render/
    editor/
      EditorState.hx
      SelectionState.hx
      panels/
    assets/
    runtime/
    hide_port/
```

The folder tree is a target organization, not a mandate to create empty abstractions in advance.

---

# 4. HIDE Reuse and Migration Strategy

## 4.1 Scope of reuse

HIDE is a reference and a possible source of reusable data-oriented systems. Candidate areas include:

- Prefab and context data models.
- Scene and node serialization.
- Resource metadata and asset conventions.
- Particle/effect definitions.
- Curves and timeline data.
- Terrain algorithms and terrain serialization.
- Shadow/lightmap baking workflows.
- CastleDB integration.
- Extension concepts for custom inspectors and editor-specific tools.

These are candidates for investigation, not approved imports. Each class and dependency must be audited before code is copied or referenced.

## 4.2 Reuse decision categories

Classify each HIDE subsystem as one of:

1. **Reuse directly:** portable Haxe logic with no browser/UI dependency and acceptable version/license terms.
2. **Adapt:** useful logic with manageable changes to dependencies, data contracts, or engine APIs.
3. **Reimplement:** desired behavior is tightly coupled to DOM/browser/editor infrastructure, but the algorithm or UX is worth preserving.
4. **Defer/drop:** unnecessary for the first Boltspark product slice or too costly to maintain.

## 4.3 Explicitly excluded HIDE components

Do not port or embed:

- HTML/CSS/DOM editor presentation.
- Browser/WebGL2 editor hosting.
- Electron/NW.js bootstrapping or packaging.
- Browser APIs, Node-specific frontend logic, DOM controls, or JavaScript bridges.
- Any hidden browser process used to implement a Boltspark editor feature.

When a HIDE tool depends on DOM behavior, preserve its data format or domain algorithm where possible and implement a new native BoltUI interaction layer.

## 4.4 HIDE audit deliverables

Before migration, produce:

- Dependency graph for each candidate module.
- List of DOM, JavaScript, browser, Node, native, and third-party dependencies.
- License and attribution inventory, including transitive dependencies.
- Data-format description and fixture corpus.
- Reuse/adapt/reimplement/defer decision with a short cost/risk assessment.
- Load/save/round-trip tests for every format marked as supported.

Do not promise 100% backward compatibility with all HIDE projects. Define a specific supported subset and test it using real project fixtures. Preserve unknown fields where possible. If Boltspark writes a format that HIDE cannot safely read, document that limitation instead of claiming bidirectional compatibility.

---

# 5. Development Roadmap and Exit Gates

No calendar estimate or sprint count is a delivery commitment until M0 has established build times, integration overhead, test reliability, and the actual agent workflow. Milestones are ordered to remove the highest-risk assumptions first.

## M0 — Windows 11 / DirectX 12 native feasibility gate

**Goal:** Prove the exact target toolchain and a minimal native Heaps application before any substantial editor/engine implementation.

Tasks:

1. Create the repository, version-control rules, CI skeleton, and toolchain lock file.
2. Pin Haxe, Heaps, HashLink, `hldx`, `format`, and the native module source/version as one tested set.
3. Build or obtain x64 HashLink runtime modules including `directx.hdll` and `dx12.hdll`.
4. Select Track A (standard DX12 runtime) or Track B (Agility-enabled runtime) and document exact native dependencies.
5. Configure `compile.hxml` with `-lib hldx` and `-D dx12`.
6. Start an application based on `hxd.App` on Windows 11.
7. Render one simple 3D object through the DX12 driver.
8. Draw one H2D overlay containing text and a clickable control.
9. Verify pointer input, keyboard event basics, resize, close, and clean shutdown.
10. Add logging for toolchain, adapter, driver, window size, and DX12 initialization failures.
11. Capture a first visual baseline and a DX12 smoke-test log.
12. Record the actual machine/GPU/driver/Windows build and all runtime module hashes.

**Exit criteria:**

- Clean checkout can be set up using documented PowerShell commands.
- Haxe compilation succeeds with the pinned dependencies.
- HashLink loads the matching DirectX modules.
- A native Windows 11 window opens with no browser-shell process.
- A 3D scene renders through Direct3D 12.
- BoltUI proof content renders through Heaps 2D in the same process.
- Input, resize, and shutdown pass repeatedly.
- CI can at least compile and run non-GPU tests; the DX12 smoke test runs on an appropriate Windows GPU runner or designated test machine.
- Toolchain lock file contains exact versions, paths, and hashes.

**Stop/go rule:** If this gate fails, do not start terrain, deferred rendering, physics, a full editor, or multi-platform support. Resolve the native DX12 and Heaps lifecycle first. Do not introduce a browser shell or silently switch to another renderer to work around a failure.

## M1 — BoltUI core foundation

**Goal:** Turn the UI proof into a reusable, testable native UI framework.

Tasks:

1. Define `UiContext`, `UiInputState`, stable widget IDs, and frame lifecycle.
2. Implement logical-coordinate geometry and deterministic row/column/stack layout.
3. Implement hit regions, event routing, hover, pointer capture, focus, and activation.
4. Add the initial widget set: label, button, toggle, checkbox, panel, separator, splitter, scrollable list, and basic property row.
5. Build an H2D draw-command renderer with resource reuse/pooling.
6. Add text measurement, clipping, scissor behavior, and basic theme/style support.
7. Add DPI scale handling and test at multiple Windows display scaling factors.
8. Implement UI diagnostics for duplicate IDs, unbalanced scopes, invalid layout, and unhandled input.
9. Unit-test layout and interaction logic independently from H2D rendering.

**Exit criteria:** A UI test application can show multiple panels, buttons, lists, and property controls; controls respond correctly to mouse and keyboard; splitter drag uses pointer capture; focus is stable; resize and DPI changes do not break layout; repeated frames do not allocate an entire new render tree.

## M2 — Editor shell and bounded viewport proof

**Goal:** Establish the layout and rendering composition for the eventual full editor.

Tasks:

1. Implement the first workspace layout with top menu/toolbar, left hierarchy region, central viewport, right inspector, and bottom output/status region.
2. Prototype the bounded 3D viewport composition alternatives in Section 3.5.
3. Add viewport resize, camera aspect updates, mouse-to-viewport coordinate mapping, and object picking proof.
4. Add panel visibility and workspace persistence.
5. Add a minimal console/log view and a simple command palette or menu command path.
6. Add keyboard shortcuts and focus-safe command routing.
7. Profile idle and active UI cost on the target machine.

**Exit criteria:** The editor shell resizes, panel regions remain stable, the central 3D view is correctly bounded, UI controls do not steal viewport input incorrectly, object picking uses correct coordinates, and layout persists across restart.

## M3 — Project, asset, scene, and serialization foundation

**Goal:** Make Boltspark projects durable and safely editable.

Tasks:

1. Define project format, versioning, stable IDs, path rules, and metadata.
2. Define asset registry/import metadata and resource cache behavior.
3. Implement scene graph, transforms, components, lifecycle, and serialization.
4. Implement prefab/instance data and explicit override rules.
5. Add project open/save/close, autosave/recovery policy, and migration infrastructure.
6. Add command-line project validation and asset-reference validation.
7. Add fixtures and round-trip tests for supported project/scene formats.
8. Add a safe backup strategy for migrations and destructive operations.

**Exit criteria:** A sample project imports a mesh and texture, creates a scene with multiple nodes, saves, closes, reopens, and preserves all tested data. Broken/missing asset references are reported clearly. Migrations preserve or deliberately transform data with recovery available.

## M4 — First usable native editor vertical slice

**Goal:** Deliver a small but complete editor workflow.

Tasks:

1. Build the hierarchy panel and property inspector using BoltUI.
2. Add selection, multi-selection only if required, and transform gizmos.
3. Add scene creation, entity creation, camera, light, and basic mesh placement.
4. Add asset browser and simple import workflow.
5. Add material assignment and a minimal material inspector.
6. Add undo/redo through a command system.
7. Add play/stop with a clear separation between editor state and runtime state.
8. Add unsaved-change prompts and error reporting through native BoltUI.

**Exit criteria:** A user can create/open a project, create/open a scene, add an object, move/rotate/scale it, assign a material and light, save, close, reopen, press Play, interact with the running scene, and stop. The workflow is reproducible and captured by automated or documented acceptance steps.

## M5 — Core 3D renderer and content workflow

**Goal:** Make the first 3D content workflow visually credible and measurable on DX12.

Tasks:

1. Establish mesh and texture import conventions.
2. Implement and validate a PBR metallic-roughness material workflow.
3. Add directional lighting and baseline shadows, then point/spot lights as supported by the chosen pipeline.
4. Verify color-space handling, HDR/LDR boundaries, tone mapping, and exposure.
5. Add a small post-processing chain based on actual product needs.
6. Compare forward and deferred approaches using the same representative scenes before committing to deferred as the default.
7. Add render diagnostics and a repeatable benchmark scene.
8. Add DX12 visual regression baselines and GPU timing where available.

**Exit criteria:** Representative content renders consistently on the supported hardware; material/scene data survives reload; visual regression baselines exist; frame-time and memory measurements are published. The renderer remains on Heaps' DX12 path unless a tested limitation justifies a custom renderer extension.

## M6 — Runtime systems and gameplay loop

**Goal:** Support a small game without linking editor-only code.

Tasks:

1. Input mapping and device abstraction.
2. Audio playback and streaming baseline using Heaps-supported facilities.
3. Select and integrate a 3D physics backend behind a Boltspark interface.
4. Prototype Jolt binding on Windows x64; validate ABI, callbacks, ownership, threading, and packaging before commitment.
5. Decide whether 2D physics requires a second backend for the first product.
6. Decide gameplay scripting scope and implementation. Do not describe Haxe scripting as sandboxed unless a real security boundary is designed and tested.
7. Define runtime asset loading and game build profile independent of BoltUI/editor tools.
8. Implement fixed/update time steps and deterministic-enough test hooks where relevant.

**Exit criteria:** A small sample game uses input, audio, physics/collision, and gameplay behavior; it builds and runs without editor modules. All native dependencies are deployed reproducibly.

## M7 — 2D workflow and authoring tools

**Goal:** Provide a credible 2D workflow using Heaps' existing 2D capabilities.

Tasks:

1. Sprite/atlas import and asset management.
2. 2D scene hierarchy, camera, sorting/layers, and tilemaps.
3. Collision layer and physics integration where required by the sample project.
4. Particle/effect runtime data model.
5. Native BoltUI curve and timeline tools based on actual content-authoring requirements.
6. Port HIDE effect data only after the format and behavior have passed the HIDE audit.
7. Add a narrow extension API for game-specific inspectors, scene gizmos, and editor sub-tools only after the core panel/widget APIs stabilize.
8. Treat CastleDB as an optional integration initially; implement a native BoltUI table/editor view only if a concrete project workflow makes it a priority.

**Exit criteria:** A playable 2D sample project can be created, edited, saved, run, and packaged. All 2D editor tools use BoltUI. Any extension API has documented lifecycle, ownership, and compatibility rules; optional CastleDB integration has import/export fixtures and schema tests.

## M8 — Advanced rendering and environment systems

**Goal:** Add advanced visual capabilities only after the baseline renderer and content workflow are stable.

Candidates (not automatic commitments):

- Baked lightmaps and light probes.
- One selected dynamic GI approach (choose after prototype and performance comparison).
- Volumetric fog and atmospheric scattering.
- Cascaded shadow maps and improved filtering.
- Terrain sculpting, texture splatting, and terrain streaming.
- Advanced particles, animation, and timeline effects.
- DX12 compute features where the Heaps/backend capability and product need justify them.

Do not implement SSGI, voxel cone tracing, SDFGI, and other competing GI approaches in parallel by default. Prototype candidates and choose one based on quality, stability, memory, GPU cost, implementation complexity, and target hardware.

**Exit criteria:** Every feature has a target scene, quality criteria, GPU/memory budget, performance benchmark, visual regression test, failure/unsupported-device behavior, and a documented decision explaining why it belongs in Boltspark.

## M9 — Packaging, profiling, hardening, and release

**Goal:** Make Boltspark predictable to install, use, diagnose, and ship games with.

Tasks:

1. Build/export pipeline for the first validated Windows target.
2. Package HashLink/HL-C runtime and all required native modules with explicit version records.
3. Package Agility SDK files only when the selected runtime build requires them; verify exact version match.
4. Asset cooking, compression, dependency collection, and reproducible packaging.
5. CPU/GPU timing, draw-call counters, memory/resource diagnostics, and crash logs.
6. Test DX12 device creation, resize, resource recreation, and device-removed handling as far as exposed by the Heaps/HashLink integration.
7. Documentation, starter projects, troubleshooting guides, and tutorial workflows.
8. Installer, Windows code signing, update strategy, and license/third-party notices.
9. Audit output artifacts and process tree to verify the native-only editor requirement.

**Exit criteria:** A clean Windows 11 machine can install the editor, open and build the sample projects, and launch exported games. DX12 native modules and optional SDK runtime dependencies are correct. All release claims are supported by the test matrix. No browser-shell dependency is present.

---

# 6. AI Agent Workflow and Engineering Governance

## 6.1 Task specification

Every agent task must state:

- Problem statement and non-goals.
- Owning module and files the agent may change.
- Inputs, outputs, public API, and serialized schema changes.
- Dependencies and assumptions, including native runtime versions where relevant.
- Acceptance tests and expected artifacts (code, tests, logs, screenshots, benchmark data, or docs).
- Integration owner and rollback/revert strategy.
- Whether the task is allowed to change `compile.hxml`, runtime modules, Haxelib versions, DX12 build configuration, or Agility SDK deployment.

Tasks should be small enough to review and integrate independently. Avoid assigning multiple agents to edit the same public API, build profile, or serialized format simultaneously.

## 6.2 Contract-first development

- Define module interfaces and data contracts before parallel implementation.
- Use architecture decision records (ADRs) for native backend, renderer, viewport composition, project format, physics, scripting, and platform support.
- Require review for public API, dependency, native build, and serialization changes.
- Pin versions and commit the toolchain lock file so agents cannot silently upgrade dependencies.
- Maintain a list of allowed/prohibited dependencies, with the native-only editor policy enforced by CI.
- Do not let agents add a new UI framework or alternate rendering backend without an ADR and successful foundation tests.

## 6.3 Integration discipline

- Each agent works from a clean branch or isolated worktree.
- Integrate frequently through small pull requests.
- Run CI against the merged result, not only agent-local builds.
- Keep an integration owner responsible for resolving API drift and rejecting duplicate/incompatible systems.
- Maintain a known-good DX12 foundation build and a tested rollback point for every milestone.
- Store DX12 test logs, screenshot baselines, toolchain hashes, and machine details as CI artifacts where possible.

## 6.4 Definition of done

A task is not complete merely because it compiles. It must:

1. Compile in the relevant build profile(s).
2. Pass unit and integration tests.
3. Include negative/error-path tests for file, asset, and native runtime operations.
4. Update API, architecture, and schema documentation when public behavior changes.
5. Pass relevant visual or performance regression checks.
6. Preserve the native-only editor constraint.
7. Include reproduction steps and evidence for any manual acceptance item.
8. Avoid unapproved dependency/version/native backend changes.

## 6.5 Agent work types

Use separate task categories to reduce integration risk:

- **Core API agent:** interfaces, data contracts, architecture docs; no concurrent implementation in the same files.
- **Feature agent:** implements one bounded component against an approved interface.
- **Test agent:** adds unit/integration/visual tests and reports missing observability.
- **Integration agent:** builds merged branches, resolves incompatibilities, checks toolchain locks.
- **Audit agent:** licensing, dependency, browser-shell scan, native module inventory, and serialization compatibility.

AI agents must not be asked to “make it work” by changing backend defines, native binaries, or package versions without reporting the exact change and its test evidence.

---

# 7. Verification, Quality, and Performance

## 7.1 Automated test layers

- **Unit tests:** math, transforms, serialization, stable IDs, asset references, layout, focus, pointer capture, and data migration.
- **Integration tests:** project open/save, asset import/cook, scene load, game build, physics lifecycle, audio loading, and runtime/editor separation.
- **Headless tests:** data/runtime systems that do not require a GPU/window. Clearly separate these from tests that require a real DX12 graphics context.
- **DX12 native smoke tests:** launch the actual Windows executable/HashLink VM, initialize the DirectX backend, create a device/swap chain, render a known scene, handle resize, and close cleanly.
- **Visual regression:** deterministic scenes with fixed camera, settings, assets, and known DX12 device/driver. Use tolerances for driver-dependent output and record the machine/driver for every baseline.
- **Performance tests:** fixed scenes and scripted interactions with repeatable asset counts, draw calls, resolution, GPU, driver, runtime, and build configuration.
- **Dependency/process audit:** inspect release artifacts and running processes to prove the absence of Electron/NW.js/CEF/WebView/Node editor dependencies.
- **Native module audit:** verify `hl.exe`, `directx.hdll`, `dx12.hdll`, architecture, version compatibility, and hashes.
- **Agility audit:** only when Track B is selected, verify `HL_DX12_AGILITY_VERSION`, Agility package version, `D3D12Core.dll`, and `d3d12SDKLayers.dll`.

A GPU renderer cannot be fully validated by headless unit tests. A headless test may validate shader source generation or render configuration, but the DX12 driver and viewport need real graphics-context tests.

## 7.2 DX12-specific acceptance checklist

The first DX12 acceptance suite must validate:

1. DX12 module loads successfully through the selected HashLink VM.
2. A compatible adapter is enumerated and device creation succeeds.
3. Swap chain/window presentation succeeds.
4. A deterministic 3D frame renders and presents.
5. H2D UI is drawn correctly in the same application.
6. Window resize updates swap-chain/back-buffer and UI/viewport dimensions without stale resources.
7. Repeated resize/minimize/restore does not leak or invalidate GPU resources.
8. Basic input and pointer-to-viewport coordinate mapping remain correct.
9. Shutdown releases resources and exits without hanging.
10. Debug/runtime logs capture useful information for DX12 initialization and device errors.
11. The test is repeated after a clean build and on the designated reference GPU/driver.

Device removal/recovery, debug layer integration, GPU crash dumps, and advanced diagnostics should be added as soon as the HashLink/Heaps integration exposes a safe way to test them. Do not claim these are supported until validated.

## 7.3 Performance budgets

Do not commit to arbitrary targets such as “under 50 MB” or “60Hz+” before defining the machine, scene, resolution, editor state, and measurement method.

During M0–M2, define and publish baselines for:

- Editor idle/active memory.
- Startup and project-open time.
- Frame time in editor UI and 3D viewport.
- Resize and layout-update cost.
- Asset import/cook throughput.
- Scene load/save time.
- CPU/GPU use and draw-call counts.
- GPU memory allocation behavior for viewport targets.

Every later optimization must be tied to a measured regression or a named product requirement.

## 7.4 Project safety and compatibility

- Keep a checked-in corpus of supported HIDE fixtures and Boltspark project fixtures.
- Test old-project open, save, reopen, and migration.
- Back up or write to a new file during schema migrations; do not risk destructive in-place conversion without recovery.
- Verify asset references after moves/renames and report missing/unsupported files clearly.
- Document exact HIDE formats and versions supported.
- Preserve unknown fields when feasible so partial format support does not silently destroy data.

---

# 8. Risk Register and Mitigations

| Risk | Why it matters | Mitigation / decision gate |
|---|---|---|
| HashLink/Heaps DX12 compatibility | Haxe bindings, VM, and native modules must be compatible as a set | Pin and test one complete toolchain; record exact versions and hashes |
| Missing/mismatched native modules | `directx.hdll` and `dx12.hdll` are separate runtime components | Add early PowerShell checks and a real native smoke test; no fallback |
| Agility SDK mismatch | Agility runtime package must match `HL_DX12_AGILITY_VERSION` | Make Agility opt-in; pin package/version; validate module and DLL paths |
| Nsight Aftermath dependency | Agility-enabled HashLink configuration may require extra SDK/DLLs | Decide whether to build with Aftermath; document the `Release` alternative where supported |
| DX12 driver/device differences | GPUs and drivers can produce different capabilities or bugs | Record GPU/driver matrix; maintain known-good reference hardware and test additional devices |
| Native UI complexity | Docking, text, focus, capture, DPI, and viewport clipping can become a major project | Build BoltUI in M1 with a small widget set and explicit acceptance tests |
| Viewport composition | A bounded viewport requires rendering, clipping, picking, and resize coordination | Prototype target/scene strategies in M2 before docking and full editor implementation |
| HIDE coupling to web UI | Reuse can accidentally import DOM/browser assumptions | Audit dependencies; reuse data/algorithms only; implement UI in BoltUI |
| Renderer scope explosion | Deferred, GI, volumetrics, and temporal effects are individually complex | Stable Heaps DX12 baseline first; benchmark forward vs deferred; choose one advanced GI path |
| Native binding instability | Physics/audio libraries may introduce ABI, memory, threading, and packaging issues | Prove bindings on Windows x64; isolate behind adapters; pin versions |
| Cross-platform drift | Native backends and system APIs differ by OS | Windows 11 DX12 first; add other platform/backend combinations only through separate validated milestones |
| Agent integration conflicts | Parallel agents can create incompatible APIs or change toolchain implicitly | Atomic tasks, module ownership, ADRs, integration owner, merged CI |
| Serialization breakage | Engine/editor changes can corrupt user projects | Versioned formats, fixture corpus, migration and round-trip tests, backups |
| Unmeasured performance promises | Memory/FPS targets may not match real workloads | Publish measured baselines before setting budgets |
| Licensing gaps | Reused code and native libraries carry obligations | Maintain license/attribution inventory before adopting/shipping components |

---

# 9. Architecture Decisions and Open Questions

## 9.1 Decisions locked for the initial foundation

1. **OS:** Windows 11 x64 is the first development target.
2. **Graphics backend:** Direct3D 12 through Heaps `hldx` with `-D dx12`.
3. **Application lifecycle:** Start with `hxd.App`.
4. **UI rendering:** BoltUI is rendered with Heaps H2D primitives and native Heaps input/event handling.
5. **No browser shell:** Electron, NW.js, CEF, Chromium shell, Tauri, Wails, WebView, DOM, HTML, and CSS UI are prohibited.
6. **Development output:** HashLink bytecode/JIT is the first iteration path.
7. **Scope order:** Native DX12 proof, BoltUI core, viewport composition, then substantial engine/editor features.
8. **HIDE strategy:** Audit individual modules; reuse portable data/algorithms only; do not port its browser UI.

## 9.2 Decisions that must be resolved during M0–M3

1. Which exact Heaps source/release will be locked: current Haxelib package or a tested upstream tag/commit?
2. Which HashLink 1.16 x64 build and `hldx` binding revision work together reliably?
3. Does the first runtime use standard DX12 or the Agility-enabled HashLink configuration?
4. What exact Windows SDK/MSVC toolchain is required to build and distribute native modules?
5. What GPU/API feature baseline is required for the first release?
6. Which viewport composition path works best under Heaps DX12?
7. What are the exact HIDE project/prefab/effect formats required for compatibility?
8. Is CastleDB a required built-in editor feature or an optional importer/integration?
9. Which physics backend can be built, debugged, and packaged reliably on Windows x64?
10. Is gameplay scripting required for the first vertical slice? If yes, which scripting model and trust boundary are intended?
11. Which two sample projects prove the product: one small 3D game and one small 2D game, or one 3D project for the first public milestone?
12. Which advanced graphics features are actual release requirements rather than aspirational roadmap items?

Linux, macOS, mobile, console, and web-game support remain uncommitted. Adding another platform requires a separate native/backend compatibility gate; the Windows DX12 editor must not be diluted with premature cross-platform abstractions.

---

# 10. First Demonstration and Immediate Work Queue

## 10.1 First demonstration

The first internal demonstration should be deliberately small:

1. Start Boltspark as a native Windows 11 application with no browser-shell process.
2. Initialize HashLink and the DirectX 12 driver.
3. Show a stable 3D test object rendered by Heaps through DX12.
4. Show a BoltUI panel, text, and clickable control rendered through H2D.
5. Resize, minimize, restore, and close the window repeatedly.
6. Verify input events and clean shutdown.
7. Record toolchain/runtime versions, GPU/driver, logs, and a screenshot.

This demonstration proves the graphics/window/UI foundation only. It is not yet a complete game editor.

## 10.2 Immediate work queue (in order)

**Task 0.1 — Lock the Windows toolchain**

- Confirm Haxe, Heaps, HashLink, `hldx`, and `format` versions.
- Confirm source/release provenance for `hl.exe`, `directx.hdll`, and `dx12.hdll`.
- Decide standard DX12 vs Agility-enabled runtime.
- Generate `docs/TOOLCHAIN_VERSIONS.md` with versions, paths, and hashes.

**Task 0.2 — Build and run the minimal Heaps DX12 app**

- Use `hxd.App`.
- Render one 3D object and a 2D overlay.
- Verify input, resize, shutdown.
- Capture a known-good DX12 smoke-test artifact.

**Task 0.3 — Implement BoltUI frame/input core**

- Stable IDs, frame lifecycle, basic layout, H2D draw list, event routing, focus, and pointer capture.
- Add unit tests for geometry/layout/input state.

**Task 0.4 — Prove bounded viewport composition**

- Render scene into a bounded viewport.
- Verify clipping, resize, coordinate mapping, picking, and DPI.

**Task 0.5 — Build the basic editor shell**

- Top bar, hierarchy area, inspector area, viewport, status/log area.
- Workspace save/restore.

Do not start the advanced rendering roadmap until these five tasks pass their respective gates.

---

# 11. Final Guidance

Boltspark's main differentiator at this stage should be its **native Windows editor foundation**, not a premature list of AAA rendering features. A reliable Heaps/HashLink DX12 runtime and a usable BoltUI framework are prerequisites for almost every later system.

The most important planning changes are:

- Make Windows 11 x64 the explicit first development target.
- Make Direct3D 12 the explicit Windows graphics backend using `-lib hldx` and `-D dx12`.
- Treat `directx.hdll` and `dx12.hdll` as separate, version-matched runtime requirements.
- Treat Agility SDK, Nsight Aftermath, and Streamline as build-configuration-specific dependencies, not universal requirements for every DX12 build.
- Move the native Heaps application and BoltUI proof to the very beginning.
- Implement BoltUI as a Heaps-rendered hybrid immediate-mode UI with retained rendering resources.
- Prove a bounded 3D viewport before building complex docking and editor tools.
- Treat HIDE as a source of portable logic and data, never as a browser UI foundation.
- Deliver a working project/scene/editor/game vertical slice before advanced GI, volumetrics, terrain, or multi-platform export.
- Replace the original fixed 20-sprint promise with milestone exit gates and evidence-based estimates.
- Require real Windows DX12 tests, visual regression, runtime-module audits, and accountable review for architecture and release decisions.

**Recommended next action:** complete M0 and produce a verified Windows 11 DX12 build report before assigning substantial BoltUI or engine work to parallel agents.

---

# References and Technical Sources

The following upstream sources were checked while preparing this revision. Their exact instructions and supported versions should be rechecked when changing the pinned toolchain.

1. **Heaps — HashLink documentation:** DirectX selection with `-lib hldx`, optional `-D dx12`, and HashLink JIT / HashLink-C workflows.  
   https://heaps.io/documentation/hashlink.html
2. **Heaps — `hxd.App` API:** application lifecycle, default 2D/3D scenes, event collection, initialization, update, and resize hooks.  
   https://heaps.io/api/hxd/App.html
3. **HashLink 1.16 — DirectX CMake configuration:** separate `directx.hdll` and `dx12.hdll` targets and their native link dependencies.  
   https://github.com/HaxeFoundation/hashlink/blob/1.16/libs/directx/CMakeLists.txt
4. **HashLink 1.16 — DirectX 12 Agility SDK setup:** matching `HL_DX12_AGILITY_VERSION`, runtime folder requirements, and optional Nsight Aftermath / Streamline notes.  
   https://github.com/HaxeFoundation/hashlink/blob/1.16/libs/directx/README.md
5. **HashLink — Releases:** stable HashLink 1.16 release notes, including substantial DirectX 12 API upgrades, and current nightly status.  
   https://github.com/HaxeFoundation/hashlink/releases
6. **Heaps — Releases:** Heaps 2.1.1 upstream release notes, including a small fix following 2.1.0 and the 2.1 series' DX12 improvements.  
   https://github.com/HeapsIO/heaps/releases
7. **Haxelib — Heaps versions:** package availability information; verify the exact published package against the selected upstream release.  
   https://lib.haxe.org/p/heaps/versions/
8. **Haxe — Download list:** current stable compiler version.  
   https://haxe.org/download/list/
9. **Microsoft — DirectX 12 Agility SDK downloads:** published SDK versions and release notes.  
   https://devblogs.microsoft.com/directx/directx12agility/
10. **Microsoft — Agility SDK getting started:** app-local runtime deployment, SDK version matching, and deployment guidance.  
    https://devblogs.microsoft.com/directx/gettingstarted-dx12agility/
