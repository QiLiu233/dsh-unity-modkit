#!/usr/bin/env bash
# 工具链自检 / 安装（版本感知 + SHA-512 校验 + 可供智能体解析的修复指令）
#   ./setup.sh              检查并按需安装
#   ./setup.sh --check      只检查，不安装
#   ./setup.sh --json       输出机器可读结果（与 --check 一起用最合适）
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

CHECK_ONLY=0; NO_VERIFY=0; FORCE_DOTNET=0; JSON=0
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    --json) JSON=1 ;;
    --no-verify) NO_VERIFY=1 ;;
    --force-dotnet) FORCE_DOTNET=1 ;;
  esac
done

ok(){   [ "$JSON" = "1" ] || printf '  [OK] %s\n' "$*"; }
bad(){  [ "$JSON" = "1" ] || printf '  [!!] %s\n' "$*"; }
info(){ [ "$JSON" = "1" ] || printf '  ->   %s\n' "$*"; }
head_(){ [ "$JSON" = "1" ] || printf '%s\n' "$*"; }

FIXES=()
MISSING=()
add_fix(){ FIXES+=("$1"); }
add_missing(){ MISSING+=("$1"); }

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

ver_ge(){
  python -c "
import sys,re
def t(v):
    m=re.match(r'(\d+(?:\.\d+)*)',v or '0')
    return tuple(int(x) for x in (m.group(1).split('.') if m else ['0']))
print(1 if t(sys.argv[1])>=t(sys.argv[2]) else 0)" "$1" "$2"
}

proxy_alive(){ curl -sS -m 6 -o /dev/null --proxy "$PROXY" https://pypi.org/simple/ 2>/dev/null; }

sha512_of(){
  if command -v sha512sum >/dev/null 2>&1; then sha512sum "$1" | awk '{print $1}'
  else python -c "import hashlib,sys;print(hashlib.sha512(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; fi
}

expected_hash(){
  python - "$1" "$2" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
try: d = json.load(open(path, encoding="utf8"))
except Exception: sys.exit(3)
for r in d.get("releases", []):
    s = r.get("sdk")
    if not isinstance(s, dict) or s.get("version") != ver: continue
    for f in s.get("files", []):
        if f.get("name") == "dotnet-sdk-win-x64.zip":
            h = (f.get("hash") or "").strip().lower()
            if h: print(h); sys.exit(0)
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
  bad "SHA-512 不匹配! 期望 ${expected:0:24}... 实际 ${actual:0:24}..."; return 1
}

# ---- 1. Python ----
check_python(){
  head_ "== 1. Python (需要 >= $REQ_PY)"
  if ! command -v python >/dev/null 2>&1; then
    bad "没有 python"
    add_fix "安装 Python >= $REQ_PY: https://www.python.org/downloads/ (勾选 Add to PATH)"
    add_missing "Python（需要 >= $REQ_PY，当前未安装）"
    PY_OK=0; PY_VER=""; return 1
  fi
  PY_VER="$(python -c 'import platform;print(platform.python_version())' 2>/dev/null)"
  if [ "$(ver_ge "$PY_VER" "$REQ_PY")" = "1" ]; then ok "python $PY_VER"; PY_OK=1; return 0; fi
  bad "python $PY_VER 低于要求 $REQ_PY"
  add_fix "升级 Python 到 >= $REQ_PY: https://www.python.org/downloads/"
  add_missing "Python（需要 >= $REQ_PY，当前 $PY_VER）"
  PY_OK=0; return 1
}

# ---- 2. UnityPy ----
check_unitypy(){
  head_ "== 2. UnityPy (需要 >= $REQ_UPY)"
  local v; v="$(python -c 'import UnityPy;print(getattr(UnityPy,"__version__","0"))' 2>/dev/null)"
  if [ -n "$v" ] && [ "$(ver_ge "$v" "$REQ_UPY")" = "1" ]; then ok "UnityPy $v"; UPY_OK=1; UPY_VER="$v"; return 0; fi
  if [ -z "$v" ]; then bad "UnityPy 未安装"; else bad "UnityPy $v 低于要求 $REQ_UPY"; fi
  add_fix "python -m pip install \"UnityPy>=$REQ_UPY\" -i $PYPI_MIRROR"
  if [ -z "$v" ]; then add_missing "UnityPy（需要 >= $REQ_UPY，当前未安装）"
  else add_missing "UnityPy（需要 >= $REQ_UPY，当前 $v）"; fi
  if [ "$CHECK_ONLY" = "1" ]; then info "运行 ./setup.sh 自动安装"; UPY_OK=0; UPY_VER="$v"; return 1; fi
  info "安装 UnityPy>=$REQ_UPY ..."
  if proxy_alive && python -m pip install --upgrade "UnityPy>=$REQ_UPY" --proxy "$PROXY" -q; then ok "已通过代理安装"
  elif python -m pip install --upgrade "UnityPy>=$REQ_UPY" -i "$PYPI_MIRROR" -q; then ok "已通过清华镜像安装"
  elif python -m pip install --upgrade "UnityPy>=$REQ_UPY" -q; then ok "已直连安装"
  else bad "安装失败"; UPY_OK=0; return 1
  fi
  UPY_VER="$(python -c 'import UnityPy;print(getattr(UnityPy,"__version__","0"))' 2>/dev/null)"
  UPY_OK=1; ok "UnityPy $UPY_VER"
}

# ---- 3. .NET SDK ----
check_dotnet(){
  head_ "== 3. .NET SDK (需要 $REQ_SDK)"
  local exe="$TOOLS/dotnet/dotnet.exe" v=""
  [ -x "$exe" ] && v="$(DOTNET_ROOT="$(cygpath -w "$TOOLS/dotnet")" "$exe" --version 2>/dev/null)"
  SDK_VER="$v"
  if [ "$v" = "$REQ_SDK" ] && [ "$FORCE_DOTNET" = "0" ]; then ok "SDK $v (精确匹配)"; SDK_OK=1; return 0; fi
  if [ -n "$v" ] && [ "$FORCE_DOTNET" = "0" ]; then
    bad "SDK $v 与要求的 $REQ_SDK 不一致"
    add_fix "$ROOT/setup.sh --force-dotnet   # 安装精确版本 $REQ_SDK"
    add_missing ".NET SDK（需要 $REQ_SDK，当前 $v）"
    SDK_OK=0; return 1
  fi
  add_fix "$ROOT/setup.sh --force-dotnet   # 安装 $REQ_SDK（含 SHA-512 校验）"
  add_missing ".NET SDK（需要 $REQ_SDK，当前未安装）"
  if [ "$CHECK_ONLY" = "1" ]; then info "运行 ./setup.sh 安装 $REQ_SDK"; SDK_OK=0; return 1; fi

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
  if [ "$got" != "1" ]; then bad "下载失败: $u1"; SDK_OK=0; return 1; fi
  info "校验下载文件 ..."
  if ! verify_sdk "$zip"; then rm -f "$zip"; bad "校验未通过, 已删除, 未安装"; SDK_OK=0; return 1; fi
  info "解压 ..."
  powershell -NoProfile -Command "Expand-Archive -Path '@@(cygpath -w "$zip")' -DestinationPath '@@(cygpath -w "$TOOLS/dotnet")' -Force"
  rm -f "$zip"
  v="$(DOTNET_ROOT="$(cygpath -w "$TOOLS/dotnet")" "$exe" --version 2>/dev/null)"
  SDK_VER="$v"
  if [ "$v" = "$REQ_SDK" ]; then ok "SDK $v"; SDK_OK=1; return 0; fi
  bad "安装后版本为 $v, 期望 $REQ_SDK"; SDK_OK=0; return 1
}

main(){
  head_ "版本清单: $VERSIONS"
  head_ "  python >= $REQ_PY | UnityPy >= $REQ_UPY | .NET SDK = $REQ_SDK | BepInEx = $REQ_BEP (需自行安装)"
  head_ ""
  PY_OK=0; UPY_OK=0; SDK_OK=0; PY_VER=""; UPY_VER=""; SDK_VER=""
  check_python || true
  check_unitypy || true
  check_dotnet || true

  local rc=0
  [ "$PY_OK" = "1" ] && [ "$UPY_OK" = "1" ] && [ "$SDK_OK" = "1" ] || rc=1

  if [ "$JSON" = "1" ]; then
    RC="$rc" PY_OK="$PY_OK" PY_VER="$PY_VER" PY_REQ="$REQ_PY" \
    UPY_OK="$UPY_OK" UPY_VER="$UPY_VER" UPY_REQ="$REQ_UPY" \
    SDK_OK="$SDK_OK" SDK_VER="$SDK_VER" SDK_REQ="$REQ_SDK" \
    FIX_LIST="$(IFS='|'; echo "${FIXES[*]:-}")" \
    MISS_LIST="$(IFS='|'; echo "${MISSING[*]:-}")" \
    python - <<'PY'
import json, os
e = os.environ
out = {
    "ok": e.get("RC") == "0",
    "checks": {
        "python":   {"ok": e.get("PY_OK") == "1",  "version": e.get("PY_VER", ""),  "required": ">=" + e.get("PY_REQ", "")},
        "unitypy":  {"ok": e.get("UPY_OK") == "1", "version": e.get("UPY_VER", ""), "required": ">=" + e.get("UPY_REQ", "")},
        "dotnetSdk":{"ok": e.get("SDK_OK") == "1", "version": e.get("SDK_VER", ""), "required": e.get("SDK_REQ", "")},
    },
    "missing": [m.strip() for m in e.get("MISS_LIST", "").split("|") if m.strip()],
    "fixes":   [f.strip() for f in e.get("FIX_LIST", "").split("|") if f.strip()],
}
print(json.dumps(out, ensure_ascii=False, indent=2))
PY
  else
    head_ ""
    head_ "== 结论"
    if [ "$rc" = "0" ]; then
      ok "解包 + 编译环境齐备"
    else
      bad "缺少 ${#MISSING[@]} 项工具："
      local m
      for m in "${MISSING[@]}"; do head_ "     - $m"; done
      head_ ""
      head_ "== 修复指令（可直接交给智能体执行）"
      local f
      for f in "${FIXES[@]}"; do head_ "   $f"; done
    fi
  fi
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
