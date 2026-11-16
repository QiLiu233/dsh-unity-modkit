# dsh-unity-modkit

Unity asset unpacker + BepInEx 6 (IL2CPP) plugin toolchain, plus **dsh-PixTiny** — a small
plugin that neutralises pixelation-style mosaic shaders by rewriting their material
parameters at the setter level.

> Language: tooling is documented in English; Chinese quick-start at the bottom.

## Contents

```BT
dsh-unity-modkit/
├─ tools/
│  ├─ setup.sh          check/install Python deps + .NET SDK (proxy → mirrors → direct, SHA-512 verified)
│  ├─ env.sh            environment for dotnet (caches redirected out of %APPDATA%)
│  ├─ unpack.py         Unity asset unpacker (info / list / mats / export / zip)
│  ├─ build-plugin.sh   build a plugin (--install copies into BepInEx/plugins)
│  ├─ new-plugin.sh     scaffold a plugin (auto-detects IL2CPP vs Mono)
│  └─ templates/        IL2CPP + Mono project templates
├─ plugins/
│  └─ pix-tiny/         PixTiny plugin source (net6.0, IL2CPP)
└─ .tools/              auto-installed SDK + caches (gitignored)
```BT

## Requirements

| Item | Version |
|---|---|
| Python | ≥ 3.8 (tested 3.12) |
| UnityPy | ≥ 1.20 (tested 1.25.4) |
| .NET SDK | 8.0.x (installed by setup.sh) |
| BepInEx | 6.0.0-be.x Unity.IL2CPP (user-installed, **not** bundled) |

## Quick start (tools)

```BASHBT
git clone <repo> && cd dsh-unity-modkit
./tools/setup.sh            # installs missing pieces
./tools/setup.sh --check    # verify only

# unpack
python tools/unpack.py info   -s "D:\Game\Game_Data\data.unity3d"
python tools/unpack.py export D:\out -s "D:\Game\Game_Data\data.unity3d"
python tools/unpack.py zip    textures.zip -d D:\out --to-desktop

# build a plugin
./tools/new-plugin.sh ../my-mod MyMod "C:\Games\SomeGame"
./tools/build-plugin.sh ../my-mod --install "C:\Games\SomeGame"
```BT

Encrypted bundles are **detected and reported, never brute-forced**. If you own the key:
`--key <hex|string>`BT. Only pass `--brute`BT if you know what it does.

## dsh-PixTiny

dsh-PixTiny hooks `Material.SetFloat`BT (string and id overloads) and rewrites:

| Property | Default written value |
|---|---|
| `_Pix`BT, `_PixelSize`BT, `_BlockSize`BT | `0.001`BT |
| `_Divisor`BT | `1000000`BT |
| `_Mosa_On`BT | `0`BT |

All three are config values (`BepInEx/config/io.github.dsh.pixtiny.cfg`BT).

It targets the **shader parameters**, not a specific game, so it is game-agnostic —
but it only works on games that drive mosaic through those properties.

### Install

1. Install BepInEx 6 IL2CPP into the game, run it once (generates `BepInEx/interop/`BT).
2. Copy `dsh-PixTiny.dll`BT into `<game>/BepInEx/plugins/`BT.
3. Launch. Log line: `[dsh-PixTiny] v1.1.0 已加载`BT.

### Build

```BASHBT
GAME_DIR="C:\Games\SomeGame" ./tools/build-plugin.sh plugins/dsh-pixtiny
```BT

or `dotnet build -c Release -p:GameDir=C:\Games\SomeGame`BT.

## License

Our code: **MIT** — see `LICENSE`BT.
Third-party components and their obligations: see `NOTICE.md`BT.

**No game assets are included or endorsed by this repository.**
Extracted textures/audio are copyrighted by their respective owners — never commit them.

## 中文速览

- 工具：`tools/`BT（解包 + 插件编译），先跑 `./tools/setup.sh`BT。
- 插件：`plugins/dsh-pixtiny`BT，编译后放进游戏 `BepInEx/plugins/`BT。
- 只处理材质参数，不含任何游戏资源；请遵守所使用游戏的最终用户协议。