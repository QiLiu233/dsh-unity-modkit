# dsh-unity-modkit

> **Status:** reference implementation, not maintained. Fork and adapt freely.

A DeepSeek Harness plugin **and** toolkit for Unity asset work:

- **DSH plugin** — registers three host tools (`unity_unpack`, `unity_build_plugin`, `unity_scaffold`)
- **Toolkit** — game-agnostic Unity unpacker (UnityPy) + BepInEx 6 plugin build chain
- **Example** — `plugins/dsh-pixtiny/`, a BepInEx plugin that neutralises pixelation shaders

## Install as a DSH plugin

```bash
# from a local checkout
dsh plugin --profile <profile> add "D:/path/to/dsh-unity-modkit"

# or from npm once published
dsh plugin --profile <profile> add dsh-unity-modkit
```

Then add `dsh-unity-modkit` to `dsh.profile.bundles` in the profile's `package.json` and restart the app.
The plugin's `cordis.patch.yml` inserts it with `toolkitDir: ''`, which means *this package's own directory* —
`tools/` sits next to `lib/`, so nothing else needs configuring.

### Tools

| Tool | What it does |
|---|---|
| `unity_unpack` | `action=info` (type/encryption census), `list`, `mats` (material → shader), `export`, `zip` |
| `unity_build_plugin` | Build a plugin project with the redirected dotnet env; `install=true` copies the DLL into the game |
| `unity_scaffold` | Create a plugin project; auto-detects IL2CPP vs Mono |

### Config (`cordis.patch.yml`)

| Key | Default | Meaning |
|---|---|---|
| `toolkitDir` | `''` | Checkout containing `tools/`; empty = package root |
| `timeoutMs` | `600000` | Default process timeout |
| `outputChars` | `12000` | Output kept (head + tail) |
| `bashPath` | `''` | Absolute bash; empty = auto-detect (PATH → Git Bash → dsh-ops bundled bash) |
| `pythonPath` | `''` | Absolute python; empty = auto-detect |

## Use the toolkit without DSH

```bash
./tools/setup.sh --check     # python / UnityPy / .NET SDK versions
./tools/setup.sh             # installs what is missing (proxy → Tsinghua PyPI → Huawei dotnet → direct, SHA-512 verified)
python tools/unpack.py info  -s "D:\Game\Game_Data\data.unity3d"
python tools/unpack.py export D:\out -s "D:\Game\Game_Data\data.unity3d"
python tools/unpack.py zip    textures.zip -d D:\out --to-desktop
```

## Build the example BepInEx plugin

```bash
GAME_DIR="C:\Games\SomeGame" ./tools/build-plugin.sh plugins/dsh-pixtiny --install "C:\Games\SomeGame"
```

Requires BepInEx 6 IL2CPP in the game, launched once so `BepInEx/interop/` exists.
BepInEx is **not** bundled; see `NOTICE.md`.

## Layout

```
package.json          DSH plugin manifest (dsh.plugin + dsh.bundle.patch)
cordis.patch.yml      inserts unity-modkit with toolkitDir: ''
lib/index.js          tool registration + process runner + executable discovery
tools/unpack.py       UnityPy front-end (info / list / mats / export / zip)
tools/setup.sh        dependency installer with SHA-512 verification
tools/env.sh          dotnet env (NuGet caches redirected out of %APPDATA%)
tools/build-plugin.sh build a plugin (--install copies into BepInEx/plugins)
tools/new-plugin.sh   scaffold (IL2CPP / Mono auto-detect)
tools/templates/      csproj + Plugin.cs templates
plugins/dsh-pixtiny/  example BepInEx plugin
```

## Verified versions

| Item | Version |
|---|---|
| Python | 3.12.10 (≥3.8) |
| UnityPy | 1.25.4 (≥1.20) |
| .NET SDK | 8.0.428 |
| BepInEx | 6.0.0-be.793 (Unity.IL2CPP) |

## Safety

- Encrypted bundles are **detected and reported, never brute-forced**; `--key` is explicit, `--brute` is opt-in.
- No game assets are shipped: extracted textures stay local and are gitignored.
- BepInEx binaries are never redistributed (LGPL-2.1) — see `NOTICE.md`.

MIT licensed — see `LICENSE`.