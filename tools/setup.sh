#!/usr/bin/env bash
# 工具链自检 / 安装（版本感知 + SHA-512 校验）
#   ./setup.sh              检查并按需安装
#   ./setup.sh --check      只检查，不安装
#   ./setup.sh --no-verify  跳过下载校验
#   ./setup.sh --force-dotnet  即使已装 SDK 也按 versions.json 重装
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$ROOT"
[ "$(basename "$ROOT")" = "tools" ] && BASE="$(cd "$ROOT/.." && pwd)"
TOOLS="$BASE/.tools"
VERSIONS="$ROOT/versions.json"
PROXY="${HTTP_PROXY:-http://127.0.0.1:7897}"
PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
META_URL="https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json"

CHECK_ONLY=0
NO_VERIFY=0
FORCE_DOTNET=0
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    --no-verify) NO_VERIFY=1 ;;
    --force-dotnet) FORCE_DOTNET=1 ;;
  esac
done

ok(){   printf '  [OK] %s\n' "$*"; }
bad(){  printf '  [!!] %s\n' "$*"; }
info(){ printf '  ->   %s\n' "$*"; }

# ---- versions.json ----
vget(){
  python -c "import json,sys
try:
    d=json.load(open(sys.argv[1],encoding='utf8'))
    print(d.get(sys.argv[2],''))
except Exception:
    print('')" "$VERSIONS" "$1"
}
REQ_PY="$(vget python)";  REQ_PY="${REQ_PY:-3.8}"
REQ_UPY="$(vget unitypy)"; REQ_UPY="${REQ_UPY:-1.20}"
REQ_SDK="$(vget dotnetSdk)"; REQ_SDK="${REQ_SDK:-8.0.428}"
REQ_BEP="$(vget bepinex)"

# 版本比较: ver_ge 1.2.3 1.2 -> 0/1
ver_ge(){
  python -c "
import sys,re
def t(v):
    m=re.match(r'(\d+(?:\.\d+)*)',v or '0')
    return tuple(int(x) for x in (m.group(1).split('.') if m else ['0']))
a=t(sys.argv[1]); b=t(sys.argv[2])
print(1 if a>=b else 0)" "$1" "$2"
}

proxy_alive(){ curl -sS -m 6 -o /dev/null --proxy "$PROXY" https://pypi.org/simple/ 2>/dev/null; }

sha512_of(){
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$1" | awk '{print $1}'
  else
    python -c "import hashlib,sys;print(hashlib.sha512(open(sys.argv[1],'rb').read()).hexdigest())" "$1"
  fi
}

expected_hash(){
  python - "$1" "$2" <<'PY'
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
                print(h); sys.exit(0)
sys.exit(4)
PY
}

verify_sdk(){
  local zip="$1" expected="${2:-}" meta="$TOOLS/releases.json"
  if [ "$NO_VERIFY" = "1" ]; then bad "已按 --no-verify 跳过校验"; return 0; fi
  if [ -z "$expected" ]; then
    curl -sSL -m 90 --proxy "$PROXY" -o "$meta" "$META_URL" 2>/dev/null || curl -sSL -m 90 -o "$meta" "$META_URL" 2>/dev/null || true
    [ -s "$meta" ] || { bad "拿不到官方哈希元数据, 跳过校验"; return 0; }
    expected="$(expected_hash "$meta" "$REQ_SDK" || true)"
    [ -n "$expected" ] || { bad "元数据里没有 $REQ_SDK 的哈希, 跳过校验"; return 0; }
  fi
  local actual; actual="$(sha512_of "$zip" | tr 'A-Z' 'a-z')"
  if [ "$actual" = "$expected" ]; then ok "SHA-512 校验通过 (${actual:0:16}...)"; return 0; fi
  bad "SHA-512 不匹配! 期望 ${expected:0:24}... 实际 ${actual:0:24}..."
  return 1
}

# ---- 1. Python ----
check_python(){
  echo "== 1. Python (需要 >= $REQ_PY)"
  command -v python >/dev/null 2>&1 || { bad "没有 python"; return 1; }
  local v; v="$(python -c 'import platform;print(platform.python_version())' 2>/dev/null)"
  if [ "$(ver_ge "$v" "$REQ_PY")" = "1" ]; then ok "python $v"
  else bad "python $v 低于要求 $REQ_PY → https://www.python.org/downloads/"; return 1
  fi
}

# ---- 2. UnityPy ----
check_unitypy(){
  echo "== 2. UnityPy (需要 >= $REQ_UPY)"
  local v; v="$(python -c 'import UnityPy;print(getattr(UnityPy,"__version__","0"))' 2>/dev/null)"
  if [ -n "$v" ] && [ "$(ver_ge "$v" "$REQ_UPY")" = "1" ]; then ok "UnityPy $v"; return 0; fi
  if [ -z "$v" ]; then bad "UnityPy 未安装"; else bad "UnityPy $v 低于要求 $REQ_UPY"; fi
  [ "$CHECK_ONLY" = "1" ] && { info "运行 ./setup.sh 安装"; return 1; }
  info "安装 UnityPy>=$REQ_UPY ..."
  if proxy_alive && python -m pip install --upgrade "UnityPy>=$REQ_UPY" --proxy "$PROXY" -q; then ok "已通过代理安装"
  elif python -m pip install --upgrade "UnityPy>=$REQ_UPY" -i "$PYPI_MIRROR" -q; then ok "已通过清华镜像安装"
  elif python -m pip install --upgrade "UnityPy>=$REQ_UPY" -q; then ok "已直连安装"
  else bad "安装失败: pip install 'UnityPy>=$REQ_UPY' -i $PYPI_MIRROR"; return 1
  fi
  local v2; v2="$(python -c 'import UnityPy;print(getattr(UnityPy,"__version__","0"))' 2>/dev/null)"
  [ "$(ver_ge "$v2" "$REQ_UPY")" = "1" ] && ok "UnityPy $v2"
}

# ---- 3. .NET SDK ----
check_dotnet(){
  echo "== 3. .NET SDK (需要 $REQ_SDK)"
  local exe="$TOOLS/dotnet/dotnet.exe" v=""
  [ -x "$exe" ] && v="$(DOTNET_ROOT="$(cygpath -w "$TOOLS/dotnet")" "$exe" --version 2>/dev/null)"
  if [ "$v" = "$REQ_SDK" ] && [ "$FORCE_DOTNET" = "0" ]; then ok "SDK $v (精确匹配)"; return 0; fi
  if [ -n "$v" ] && [ "$FORCE_DOTNET" = "0" ]; then
    bad "SDK $v 与要求的 $REQ_SDK 不一致"
    info "如需固定版本: ./setup.sh --force-dotnet"
    return 1
  fi
  [ "$CHECK_ONLY" = "1" ] && { info "运行 ./setup.sh 安装 $REQ_SDK"; return 1; }

  mkdir -p "$TOOLS"
  local zip="$TOOLS/dotnet-sdk.zip" got=0
  local u1="https://builds.dotnet.microsoft.com/dotnet/Sdk/$REQ_SDK/dotnet-sdk-$REQ_SDK-win-x64.zip"
  local u2="https://mirrors.huaweicloud.com/dotnet/Sdk/$REQ_SDK/dotnet-sdk-$REQ_SDK-win-x64.zip"
  for u in "$u1" "$u2"; do
    for opt in "" "--proxy $PROXY"; do
      info "下载 $u $opt"
      if curl -sSL -m 900 $opt -o "$zip" "$u" && [ "$(stat -c%s "$zip" 2>/dev/null || echo 0)" -gt 10000000 ]; then got=1; break 2; fi
    done
  done
  if [ "$got" != "1" ]; then bad "下载失败: $u1"; return 1; fi
  info "校验下载文件 ..."
  if ! verify_sdk "$zip"; then rm -f "$zip"; bad "校验未通过, 已删除, 未安装"; return 1; fi
  info "解压 ..."
  powershell -NoProfile -Command "Expand-Archive -Path '@@(cygpath -w "$zip")' -DestinationPath '@@(cygpath -w "$TOOLS/dotnet")' -Force"
  rm -f "$zip"
  v="$(DOTNET_ROOT="$(cygpath -w "$TOOLS/dotnet")" "$exe" --version 2>/dev/null)"
  [ "$v" = "$REQ_SDK" ] && ok "SDK $v" || { bad "安装后版本为 $v, 期望 $REQ_SDK"; return 1; }
}

main(){
  echo "版本清单: $VERSIONS"
  echo "  python >= $REQ_PY | UnityPy >= $REQ_UPY | .NET SDK = $REQ_SDK | BepInEx = $REQ_BEP (需自行安装)"
  echo
  local rc=0
  check_python || rc=1
  check_unitypy || rc=1
  check_dotnet || rc=1
  echo
  echo "== 结论"
  if [ "$rc" = "0" ]; then ok "解包 + 编译环境齐备"; else bad "有缺项, 见上面提示"; fi
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
