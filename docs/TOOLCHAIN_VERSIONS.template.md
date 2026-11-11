# Windows 11 / DirectX 12 toolchain lock (fill in after first successful run)

- OS edition/build (Windows 11):
- Architecture: x64
- CPU:
- GPU:
- GPU driver version/date:
- Direct3D 12 feature level reported by the device:
- Haxe (`haxe --version`):
- HashLink (`hl --version`):
- HashLink distribution source/release asset/commit:
- HashLink native module `directx.hdll` path/version/hash:
- HashLink native module `dx12.hdll` path/version/hash:
- HashLink DX12 build configuration (including Agility/Aftermath choice):
- `HL_DX12_AGILITY_VERSION` used by the HashLink build:
- Installed DirectX 12 Agility SDK package version:
- `D3D12/D3D12Core.dll` version/hash:
- `D3D12/d3d12SDKLayers.dll` version/hash:
- Heaps (`haxelib list`):
- `format` version:
- `hldx` version:
- Backend: `hldx` + `-D dx12` / Direct3D 12
- Haxe build config: `compile.hxml`
- Date verified:

## Backend compatibility rule

Keep the HashLink VM, `directx.hdll`, `dx12.hdll`, and `hldx` binding versions aligned as one tested set. Keep the Agility SDK package exactly matched to `HL_DX12_AGILITY_VERSION`. Agents must not update Haxe, HashLink, Heaps, `format`, `hldx`, the Agility SDK, or native modules independently. Any upgrade requires a clean compile and the full Windows native acceptance suite.
