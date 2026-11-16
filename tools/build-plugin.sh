#!/usr/bin/env bash
# 编译 BepInEx 插件
#   ./build-plugin.sh [工程目录]
#   ./build-plugin.sh --check
#   ./build-plugin.sh [工程目录] --install <游戏根目录>   # 编译后自动复制到 plugins
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT/env.sh"

PROJ="."
INSTALL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      echo "dotnet        : $(dotnet --version 2>&1)"
      echo "DOTNET_ROOT   : $DOTNET_ROOT"
      echo "APPDATA       : $APPDATA"
      echo "NUGET_PACKAGES: $NUGET_PACKAGES"
      exit 0 ;;
    --install)
      INSTALL="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,6p' "$0"; exit 0 ;;
    *) PROJ="$1"; shift ;;
  esac
done

PROJ="${PROJ:-.}"
[ -d "$PROJ" ] || { echo "目录不存在: $PROJ" >&2; exit 1; }
cd "$PROJ" || exit 1
ls *.csproj >/dev/null 2>&1 || { echo "$PROJ 里没有 .csproj" >&2; exit 1; }

echo "== 工程 $(pwd)"
echo "== dotnet $(dotnet --version)"
dotnet build -c Release --nologo
rc=$?
echo
if [ "$rc" = "0" ]; then
  echo "== 产物:"
  find . -path ./obj -prune -o -name "*.dll" -path "*Release*" -print 2>/dev/null | sed 's/^/   /'
  if [ -n "${INSTALL:-}" ]; then
    DEST="$INSTALL/BepInEx/plugins"
    if [ -d "$INSTALL/BepInEx" ]; then
      mkdir -p "$DEST"
      cp -f bin/Release/*.dll "$DEST"/ 2>/dev/null
      echo "== 已安装到 $DEST"
    else
      echo "!! $INSTALL 下没有 BepInEx, 跳过安装" >&2
    fi
  else
    echo
    echo "把 dll 复制到 <游戏>/BepInEx/plugins/ 即可 (或加 --install <游戏根目录>)"
  fi
else
  echo "== 编译失败 (退出码 $rc)"
fi
exit "$rc"
