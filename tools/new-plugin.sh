#!/usr/bin/env bash
# 生成 BepInEx 插件工程骨架 (自动识别 IL2CPP / Mono)
#   ./new-plugin.sh <目标目录> <插件名> <游戏根目录> [GUID]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -lt 3 ]; then
  echo "用法: $0 <目标目录> <插件名> <游戏根目录> [GUID]" >&2
  exit 1
fi

DEST="$1"; NAME="$2"; GAME="$3"; GUID="${4:-com.example.mod}"
[ "$GUID" = "com.example.mod" ] && GUID="com.example.$(echo "$NAME" | tr '[:upper:]' '[:lower:]')"

GW="$(cygpath -w "$GAME" 2>/dev/null || echo "$GAME")"
GU="$(cygpath -u "$GAME" 2>/dev/null || echo "$GAME")"
[ -d "$GU/BepInEx/core" ] || { echo "没找到 $GAME/BepInEx/core, 请确认游戏根目录" >&2; exit 1; }
mkdir -p "$DEST"

if [ -f "$GU/GameAssembly.dll" ] || [ -d "$GU/BepInEx/interop" ]; then
  MODE="il2cpp"
  [ -d "$GU/BepInEx/interop" ] || {
    echo "!! IL2CPP 游戏但还没有 BepInEx/interop: 先启动一次游戏" >&2
    exit 1
  }
  sed -e "s|@NAME@|$NAME|g" -e "s|@GUID@|$GUID|g" -e "s|@GAMEROOT@|$GW|g" \
      "$ROOT/templates/plugin.csproj.tpl" > "$DEST/$NAME.csproj"
  sed -e "s|@NAME@|$NAME|g" -e "s|@GUID@|$GUID|g" \
      "$ROOT/templates/Plugin.cs.tpl" > "$DEST/Plugin.cs"
else
  MODE="mono"
  MANAGED="$(ls -d "$GU"/*_Data/Managed 2>/dev/null | head -1 || true)"
  [ -n "$MANAGED" ] || { echo "!! Mono 游戏但找不到 *_Data/Managed" >&2; exit 1; }
  MW="$(cygpath -w "$MANAGED" 2>/dev/null || echo "$MANAGED")"
  sed -e "s|@NAME@|$NAME|g" -e "s|@GUID@|$GUID|g" -e "s|@GAMEROOT@|$GW|g" -e "s|@MANAGED@|$MW|g" \
      "$ROOT/templates/plugin.mono.csproj.tpl" > "$DEST/$NAME.csproj"
  sed -e "s|@NAME@|$NAME|g" -e "s|@GUID@|$GUID|g" \
      "$ROOT/templates/Plugin.mono.cs.tpl" > "$DEST/Plugin.cs"
fi

echo "模式: $MODE"
echo "已生成: $DEST/$NAME.csproj"
echo "        $DEST/Plugin.cs"
echo "下一步: $ROOT/build-plugin.sh \"$DEST\" --install \"$GAME\""
