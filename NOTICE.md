# Third-party notices

This repository's own code is MIT (see `LICENSE`). It depends on / interoperates with
the following projects. **None of their binaries are redistributed here.**

| Component | License | How this repo uses it | Obligations if you redistribute |
|---|---|---|---|
| [BepInEx](https://github.com/BepInEx/BepInEx) 6 (IL2CPP) | LGPL-2.1 | Build-time reference only; user installs it themselves | Bundling requires LGPL compliance: ship license, provide source, keep it replaceable |
| [HarmonyX](https://github.com/BepInEx/HarmonyX) (`0Harmony.dll`) | MIT | Provided by BepInEx at runtime | Include copyright + permission notice if you ship the DLL |
| [UnityPy](https://github.com/K0lb3/UnityPy) | MIT | `pip install UnityPy` (not vendored) | Include notice if bundled |
| [.NET SDK](https://github.com/dotnet/runtime) | MIT | Build tooling only, installed by `tools/setup.sh` | Not distributed by this repo |

## Publishing checklist

- [ ] Do **not** commit any game-derived files (textures, audio, models, extracted bundles).
- [ ] Do **not** commit `BepInEx/`, `winhttp.dll`, `doorstop_config.ini`, or `interop/`.
- [ ] Keep `bin/`, `obj/`, `.tools/` out of the repo (already in `.gitignore`).
- [ ] Replace the copyright holder placeholder in `LICENSE`.
- [ ] If you add a binary release, attach only your own DLL and the MIT notice.

## Scope caveat

dsh-PixTiny only rewrites shader material parameters. It contains no game code, no
bypass of copy protection, and no redistributed assets. Whether modifying a given
game is permitted is governed by that game's EULA — comply with it, and do not
publish patches that require redistributing someone else's content.
