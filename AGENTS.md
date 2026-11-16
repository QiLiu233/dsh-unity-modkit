# AGENTS.md

> Guidance for AI coding agents working on this repository.

## What this is

A **reference implementation**, not a maintained product. It contains:

- a game-agnostic Unity asset unpacker (`tools/unpack.py`)
- a BepInEx 6 (IL2CPP) plugin build/scaffold toolchain (`tools/`)
- a `unity_env` tool that reports/repairs the toolchain (missing tools go to the user first)
- one example plugin, `plugins/dsh-pixtiny/`, that neutralises pixelation-style
  mosaic shaders by rewriting material parameters at the setter level

The example plugin was validated against one specific game; treat that game as a
test fixture only. There is no support contract, no issue triage, and no roadmap.

## Layout

```
package.json            DSH plugin manifest (dsh.plugin + dsh.bundle.patch)
cordis.patch.yml        inserts unity-modkit (toolkitDir '' = package root)
lib/index.js            tool registration, process runner, executable discovery
tools/unpack.py         UnityPy front-end: info / list / mats / export / zip
tools/setup.sh          installs Python deps + .NET SDK (proxy → mirrors → direct, SHA-512 checked)
tools/env.sh            dotnet environment (caches redirected out of %APPDATA%)
tools/build-plugin.sh   build a plugin; --install copies into BepInEx/plugins
tools/new-plugin.sh     scaffold; auto-detects IL2CPP vs Mono
tools/templates/        csproj + Plugin.cs templates for both runtimes
plugins/dsh-pixtiny/    example plugin (net6.0, IL2CPP)
```

## Adapting to a different game

1. **Is the game IL2CPP?** `GameAssembly.dll` present → yes. Mono games need
   BepInEx 5 and `tools/templates/plugin.mono.csproj.tpl`.
2. **Install BepInEx 6 (IL2CPP) manually, launch the game once.** This generates
   `BepInEx/interop/`; nothing compiles without it.
3. **Find the mosaic shaders.** Either:
   - `python tools/unpack.py mats -s <bundle>` and look for `Mosaic` in the shader
     column, or
   - add a temporary probe component that logs every renderer whose
     `material.shader.name` contains `Mosaic`, plus the properties it actually has.
4. **Read the real property names.** Common families:
   - `_Pix` / `_PixelSize` / `_BlockSize` — block size, smaller = less mosaic
   - `_Divisor` — block count divisor, larger = less mosaic
   - `_Mosa_On` — on/off float, `0` = off
   Never assume: dump them first.
5. **Patch at the setter, not the field.** Many engines (Live2D/Cubism especially)
   re-upload material parameters every frame, so periodically writing values from
   an `Update()` loop loses the race. Use a Harmony prefix on
   `Material.SetFloat(string, float)` and `Material.SetFloat(int, float)`.
6. **Rebuild and deploy:**

```bash
GAME_DIR="C:\\Games\\SomeGame" ./tools/build-plugin.sh plugins/dsh-pixtiny --install "C:\\Games\\SomeGame"
```

## Verified pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Values written from `Update()` get reverted | renderer re-uploads material each frame | patch `Material.SetFloat` |
| Swapping the mosaic shader to a plain Unlit makes the mesh render **solid black** | blend state (`_SrcColor`/`_DstColor`) and mask keywords are lost | do not swap shaders blindly; replicate blend/mask state or only tweak parameters |
| Layer disappears leaving a hole | the mosaic drawable *is* the artwork, not an overlay | shrink pixel parameters instead of disabling the renderer |
| Nothing matches by name | engines name materials/drawables by index (`ArtMesh41`, `texture_00_3`) | match on **shader name + property presence**, not object names |
| `AudioClip.samples` raises `FmodError` | FMOD-banked audio needs bank data | skip those clips; the exporter already treats it as a skip, not a failure |
| Build fails with `CS0012 ... Il2Cppmscorlib` | missing interop reference | add the `Il2Cppmscorlib` reference (already in the example csproj) |

## Do not

- Do **not** commit extracted game assets (textures/audio/models) — copyrighted.
- Do **not** vendor BepInEx binaries. It is LGPL-2.1; keep it a user-provided dependency.
- Do **not** brute-force encrypted bundles by default. `--key` is explicit; `--brute` is opt-in.
- Do **not** claim the plugin works for a specific commercial game in the README.

## 中文速览

这是参考实现，不维护。适配新游戏的顺序：确认 IL2CPP → 装 BepInEx 6 并启动一次生成 interop
→ 用 `unpack.py mats` 或临时探针找出 Mosaic shader 和真实属性名 → 在 `Material.SetFloat` 层拦截改写
→ 编译后用 `--install` 部署。不要把游戏资源或 BepInEx 二进制提交进仓库。