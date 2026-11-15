# Windows 11 / DirectX 12 toolchain lock — verified 2026-11-11

- OS edition/build (Windows 11): Windows 11 Pro, build 26300 (x64)
- Architecture: x64
- CPU: 12th Gen Intel(R) Core(TM) i7-12700K
- GPU: NVIDIA GeForce RTX 3080
- GPU driver version/date: 32.0.16.2114 (2026-10-27)
- Direct3D 12 feature level reported by the device: 12_1 (RTX 3080); DX12 driver initialized with default adapter (no explicit device name set by Heaps DX12Driver at M0)
- Haxe (`haxe --version`): **5.0.0-preview.1+dcda605** (pinned development build, dated 2025-10-23) — installed at `toolchain/haxe-dev`
  - **Why a dev build:** Haxe 4.3.7 (latest stable) has **no** native `hl_carray` codegen (`genhl.ml` has zero `ACArray` support; verified from 4.3.7 source). Heaps 2.1.0's DX12 driver (`h3d/impl/DX12Driver.hx`) requires `hl.CArray` element access that 4.3.7 cannot compile correctly, and 4.3.7's stdlib declares `carray_get`/`carray_length` primitives that no released HashLink exports (verified against HashLink 1.16.0 `libhl.dll` PE exports: only `alloc_carray` + `carray_blit`). Dev builds 2024-12-20 through 2025-10-23 compile and run the full project; 2025-10-25+ is broken by Haxe commit `70820f1` ("Refactor event loops" — removes `EventLoop.progress` called by Heaps 2.1.0 `hxd/System.hl.hx:157`). The 2025-10-23 build is therefore the **newest working** compiler for Heaps 2.1.0 + HashLink 1.16 + DX12.
  - Ratified by the user on 2026-11-11.
  - The adjacent compiler runtime DLLs are tracked so the pinned compiler can
    start on a clean hosted Windows worker: `libmbedcrypto.dll`
    `C66623ED439BC779C09BECF76278EB6615C05D42374AA75CB0592B86D4C9AD62`,
    `libmbedtls.dll` `6E329DB9D8B65B859D89D295D37A2ECCB93EE09E4A3AE17B203EBB14F1DEF18B`,
    `libmbedx509.dll` `1248D18B14471D606AA11A97039252CFDADB8D1712CA18D49A36A76317F683C3`,
    `libpcre2-8-0.dll` `A794A85AEBE6784AB3491F7EFF353CCE7AF2CB799619E635B49E0C55276A0911`,
    and `zlib1.dll` `A9ADF9FEFE5CA7F283A3BF0488C99AB845B74310C32C6F64025F324676743660`.
- Haxe stable reference (not used to build): 4.3.7 at `toolchain/haxe` (kept for reference only; DX12 is not functional with it)
- HashLink (`hl --version`): **1.16.0** — official win64 binary release, at `toolchain/hashlink`
- HashLink distribution source/release asset/commit: `hashlink-1.16-win64.zip` from https://github.com/HaxeFoundation/hashlink/releases/tag/1.16 (official binary, no Agility-specific build)
- HashLink native module `directx.hdll` path/version/hash: `toolchain/hashlink/directx.hdll` — sha256 `F8737DDFC595987585708C3A2297A9322EE556694022DC31F0B2DAD21760776C`
- HashLink native module `dx12.hdll` path/version/hash: `toolchain/hashlink/dx12.hdll` — sha256 `D18B3B184C556A855BF3E954A232866062862F71FEFF0FE59EF87694552BD10F` (exports 198 `dx12_*`/`hlp_*` primitives, matching the `hldx` 1.16.0 binding source exactly)
- HashLink VM core `libhl.dll` hash: sha256 `6E2B3FCBD4B309C562CE931D49613EC0717041E11710A5B034F8240355AA247B`
- HashLink shader compiler DLLs: `dxcompiler.dll` sha256 `5888D3E590F5BFD8743484E7F31313996734ADEC5741506271A5C6368CBE8BA9`, `dxil.dll` sha256 `0CF5FA4B90F74550166108B3870C883F4A85243976B246B1DA3EA90AD5B92015` (ship beside `dx12.hdll` in the official build)
- HashLink DX12 build configuration (including Agility/Aftermath choice): **standard DX12 build, no Agility SDK**. The official HashLink 1.16.0 binary does not bundle the Agility SDK and does not require it (verified by successful DX12 runtime evidence; also verified against the 1.16 source that the earlier Agility hard-requirement was wrong and has been removed). The `D3D12/` Agility folder beside `hl.exe` is **not required and not present**.
- `HL_DX12_AGILITY_VERSION` used by the HashLink build: n/a (not defined in the official 1.16.0 binary build configuration)
- Installed DirectX 12 Agility SDK package version: n/a (not installed, not required)
- `D3D12/D3D12Core.dll` version/hash: n/a
- `D3D12/d3d12SDKLayers.dll` version/hash: n/a
- Heaps (`haxelib list`): **heaps 2.1.0** (project-local repository `toolchain/haxelib`)
  - Local compatibility patch in `h3d/Engine.hx`: avoid reapplying the current window display mode during engine initialization. The redundant `Windowed` request made hldx call `ChangeDisplaySettingsEx`, which resets the display color ramp and briefly removes f.lux tint.
- `format` version: **3.8.0**
- `hldx` version: **1.16.0**
- HashLink Haxe/C support library: **1.16.0** (source tag `1.16`)
- hlfreetype: **1.0.0**, pinned project-local source at commit `56c8aac44b1874f0e50c61d970fe8c171c3c5e70` (`third_party/hlfreetype`; upstream archive SHA256 `1D8320D1CAF8C36A3FB9331E3EAC43341080395FDE0039AB3D8F0A2EEBBD57F2`)
- FreeType: **2.14.3** / tag `VER-2-14-3`, commit `0a0221a1347e2f1e07c395263540026e9a0aa7c7`; source archive SHA256 `A4C2B6F10C8C78013B410B1ED861485B1BE413F424BF9A6F92AABA844E13C934`. Source is installed project-locally by `tools/build.ps1 -InstallDependencies` and statically linked into `freetype.hdll`.
- Project-built `freetype.hdll` verification hash: sha256 `2258306D2D51367B6D41024ADA5A11195868394FA593BBE196006D79FC8C0432` (x64 Release, VS2026 v145; output can change with compiler/toolset changes and must then be re-recorded).
- WinPixEventRuntime: **1.0.240308001** (NuGet package SHA256 `726ACC93D6968E2146261A1E415521747D50AD69894C2B42B5D0D4C29FD66EC4`)
- Backend: `hldx` + `-D dx12` / Direct3D 12
- Haxe build config: `compile.hxml` (`-cp third_party/hlfreetype -lib heaps -lib format -lib hldx --macro freetype.heaps.Macro.main() -D dx12 -D hl_ver=1.16.0 -debug -hl bin/boltspark.hl`)
- Runtime proof: `[M0] renderer driver = h3d.impl.DX12Driver` logged at startup (`bin/runlog.txt`); window "Boltspark Engine" renders 3D cube + H2D editor chrome (`bin/m0_window.png`, `bin/m0_input_test.png`)
- Date verified: 2026-11-11

## Environment variables (project-local toolchain)

User-level (set on 2026-11-11; nothing on C: except the unavoidable pre-existing machine-level `HAXEPATH`/`NEKO_INSTPATH` leftovers from the old installer, which are harmless dead paths and could only be removed with admin rights):

- `HAXEPATH` = `D:\Giochi\BoltSpark Engine\toolchain\haxe-dev`
- `HAXE_STD_PATH` = `D:\Giochi\BoltSpark Engine\toolchain\haxe-dev\std`
- `HAXELIB_PATH` = `D:\Giochi\BoltSpark Engine\toolchain\haxelib`
- `NEKO_INSTPATH` = `D:\Giochi\BoltSpark Engine\toolchain\neko`
- User `PATH` includes `toolchain\haxe-dev` and `toolchain\hashlink` (before `toolchain\haxe`)

Scripts under `tools/` also set these per-session and do not depend on PATH alone.

## stdlib note (CArray)

The Heaps DX12 driver requires `hl.CArray`. The pinned dev compiler ships its own std with native CArray codegen (`untyped this[index]`) that only needs the `alloc_carray` primitive HashLink 1.16.0 provides. The 4.3.7 stock std at `toolchain/haxe/std/hl/CArray.hx` was locally patched during diagnosis (original kept as `CArray.hx.original-4.3.7-stock`); that patch is **not used** by the pinned compiler and exists only as diagnostic documentation. Do not build the project with `toolchain/haxe` (4.3.7).

## Backend compatibility rule

Keep the HashLink VM, `directx.hdll`, `dx12.hdll`, `libhl.dll`, and `hldx` binding versions aligned as one tested set (official 1.16.0 release). Keep the pinned Haxe dev build exactly as recorded (any newer dev build past 2025-10-23 breaks Heaps 2.1.0; any stable release cannot run DX12 with Heaps 2.1.0). hlfreetype and FreeType are also a tested pair and must remain at the pins above unless their native module, exact-size metrics, dynamic cache repro, and editor rendering are re-verified. Agents must not update these dependencies or native modules independently. Any upgrade requires a clean compile and the full Windows native acceptance suite (`tests/native-foundation-acceptance.md`).
