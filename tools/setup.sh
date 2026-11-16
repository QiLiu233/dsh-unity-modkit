#!/usr/bin/env bash
# 工具链自检 / 安装（带 SHA-512 校验）
#   ./setup.sh             检查并按需安装
#   ./setup.sh --check     只检查
#   ./setup.sh --no-verify 跳过下载校验（不推荐）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$ROOT")" = "tools" ]; then
  BASE="$(cd "$ROOT/.." && pwd)"
else
  BASE="$ROOT"
fi
TOOLS="$BASE/.tools"
PROXY="${HTTP_PROXY:-http://127.0.0.1:7897}"
PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
DOTNET_SDK="${DOTNET_SDK_VERSION:-8.0.428}"
DOTNET_DIR="$TOOLS/dotnet"
META_URL="https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json"
CHECK_ONLY=0
NO_VERIFY=0

ok(){   printf '  [OK] %s\n' "$*"; }
bad(){  printf '  [!!] %s\n' "$*"; }
info(){ printf '  ->   %s\n' "$*"; }

proxy_alive(){ curl -sS -m 6 -o /dev/null --proxy "$PROXY" https://pypi.org/simple/ 2>/dev/null; }

sha512_of(){
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$1" | awk '{print $1}'
  else
    python -c "import hashlib,sys;print(hashlib.sha512(open(sys.argv[1],'rb').read()).hexdigest())" "$1"
  fi
}

expected_hash(){
  local meta="$1" version="$2"
  python - "$meta" "$version" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path, encoding="utf8"))
except Exception:
    sys.exit(3)
for r in d.get("releases", []):
    s = r.get("sdk")
    if not isinstance(s, dict) or s.get("version") != ver:
        continue
    for f in s.get("files", []):
        if f.get("name") == "dotnet-sdk-win-x64.zip":
            h = (f.get("hash") or "").strip().lower()
            if h:
                print(h)
                sys.exit(0)
sys.exit(4)
PY
}

# verify_sdk <zip> [expected_hash]
verify_sdk(){
  local zip="$1" expected="${2:-}" meta="$TOOLS/releases.json"
  if [ "$NO_VERIFY" = "1" ]; then
    bad "已按 --no-verify 跳过校验"
    return 0
  fi
  if [ -z "$expected" ]; then
    if ! curl -sSL -m 90 --proxy "$PROXY" -o "$meta" "$META_URL" 2>/dev/null || [ ! -s "$meta" ]; then
      curl -sSL -m 90 -o "$meta" "$META_URL" 2>/dev/null || true
    fi
    if [ ! -s "$meta" ]; then
      bad "拿不到官方哈希元数据, 本次跳过校验"
      return 0
    fi
    expected="$(expected_hash "$meta" "$DOTNET_SDK" || true)"
    if [ -z "$expected" ]; then
      bad "元数据里没有 $DOTNET_SDK 的哈希, 跳过校验"
      return 0
    fi
  fi
  local actual
  actual="$(sha512_of "$zip" | tr 'A-Z' 'a-z')"
  if [ "$actual" = "$expected" ]; then
    ok "SHA-512 校验通过 (${actual:0:16}...)"
    return 0
  fi
  bad "SHA-512 不匹配!"
  bad "  期望: ${expected:0:32}..."
  bad "  实际: ${actual:0:32}..."
  return 1
}

check_python(){
  echo "== 1. Python"
  if command -v python >/dev/null 2>&1; then
    ok "python $(python --version 2>&1 | awk '{print $2}')"
  else
    bad "没有 python, 请先安装 Python 3.8+"
    exit 1
  fi
}

ensure_unitypy(){
  echo "== 2. UnityPy"
  if python -c "import UnityPy" 2>/dev/null; then
    ok "UnityPy $(python -c 'import UnityPy;print(getattr(UnityPy,"__version__","?"))' 2>/dev/null)"
    return 0
  fi
  bad "UnityPy 未安装"
  [ "$CHECK_ONLY" = "1" ] && { info "运行 ./setup.sh 安装"; return 1; }
  info "尝试安装 ..."
  if proxy_alive && python -m pip install --upgrade UnityPy --proxy "$PROXY" -q; then ok "已通过代理安装"
  elif python -m pip install --upgrade UnityPy -i "$PYPI_MIRROR" -q; then ok "已通过清华镜像安装"
  elif python -m pip install --upgrade UnityPy -q; then ok "已直连安装"
  else bad "安装失败: pip install UnityPy -i $PYPI_MIRROR"; return 1
  fi
  return 0
}

ensure_dotnet(){
  echo "== 3. .NET SDK"
  if [ -x "$DOTNET_DIR/dotnet.exe" ]; then
    ok "SDK $(DOTNET_ROOT="$DOTNET_DIR" "$DOTNET_DIR/dotnet.exe" --version 2>/dev/null)"
    return 0
  fi
  bad "本地 SDK 不存在 ($DOTNET_DIR)"
  [ "$CHECK_ONLY" = "1" ] && { info "运行 ./setup.sh 安装"; return 1; }

  mkdir -p "$TOOLS"
  local zip="$TOOLS/dotnet-sdk.zip" got=0
  local u1="https://builds.dotnet.microsoft.com/dotnet/Sdk/$DOTNET_SDK/dotnet-sdk-$DOTNET_SDK-win-x64.zip"
  local u2="https://mirrors.huaweicloud.com/dotnet/Sdk/$DOTNET_SDK/dotnet-sdk-$DOTNET_SDK-win-x64.zip"
  for u in "$u1" "$u2"; do
    for opt in "" "--proxy $PROXY"; do
      info "下载 $u $opt"
      if curl -sSL -m 900 $opt -o "$zip" "$u" && [ "$(stat -c%s "$zip" 2>/dev/null || echo 0)" -gt 10000000 ]; then got=1; break 2; fi
    done
  done
  if [ "$got" != "1" ]; then
    bad "下载失败, 手动下载后解压到 $DOTNET_DIR"
    bad "  $u1"
    return 1
  fi

  info "校验下载文件 ..."
  if ! verify_sdk "$zip"; then
    rm -f "$zip"
    bad "校验未通过, 已删除下载文件, 未安装"
    return 1
  fi

  info "解压 ..."
  powershell -NoProfile -Command "Expand-Archive -Path '@@(cygpath -w "$zip")' -DestinationPath '@@(cygpath -w "$DOTNET_DIR")' -Force"
  rm -f "$zip"
  if [ -x "$DOTNET_DIR/dotnet.exe" ]; then
    ok "SDK $(DOTNET_ROOT="$DOTNET_DIR" "$DOTNET_DIR/dotnet.exe" --version 2>/dev/null)"
  else
    bad "解压后没有 dotnet.exe"
    return 1
  fi
  return 0
}

main(){
  local arg="${1:-}"
  [ "$arg" = "--check" ] && CHECK_ONLY=1
  [ "$arg" = "--no-verify" ] && NO_VERIFY=1

  check_python
  ensure_unitypy; local u=$?
  ensure_dotnet; local d=$?

  echo "== 4. 结论"
  if [ "$u" = "0" ] && [ "$d" = "0" ]; then
    ok "解包 + 编译环境齐备"
  else
    bad "有缺项, 见上面提示"
    return 1
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
