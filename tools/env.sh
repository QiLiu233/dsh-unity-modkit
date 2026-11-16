#!/usr/bin/env bash
# source 之后: dotnet 与工具脚本可直接使用
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$ROOT")" = "tools" ]; then
  BASE="$(cd "$ROOT/.." && pwd)"
else
  BASE="$ROOT"
fi
TOOLS="$BASE/.tools"

w(){ cygpath -w "$1" 2>/dev/null || echo "$1"; }

export DOTNET_ROOT="$(w "$TOOLS/dotnet")"
export PATH="$TOOLS/dotnet:$ROOT:$PATH"
# 必须重定向: 默认 %APPDATA%\NuGet 无写权限时 restore 会失败
export DOTNET_CLI_HOME="$(w "$TOOLS/homes/dotnet")"
export APPDATA="$(w "$TOOLS/homes/appdata")"
export NUGET_PACKAGES="$(w "$TOOLS/homes/nuget")"
export NUGET_HTTP_CACHE_PATH="$(w "$TOOLS/homes/nuget-http")"
export LOCALAPPDATA="$(w "$TOOLS/homes/localappdata")"
export TMP="$(w "$TOOLS/homes/tmp")"
export TEMP="$TMP"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
mkdir -p "$TOOLS/homes/dotnet" "$TOOLS/homes/appdata" "$TOOLS/homes/nuget" \
         "$TOOLS/homes/nuget-http" "$TOOLS/homes/localappdata" "$TOOLS/homes/tmp" 2>/dev/null || true
