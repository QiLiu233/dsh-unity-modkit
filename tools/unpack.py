# -*- coding: utf-8 -*-
"""
通用 Unity 资源解包工具 (UnityPy)

用法:
    python unpack.py info   -s <路径>                     检测类型/加密/统计
    python unpack.py list   -s <路径> [-t 类型] [-k 关键字] [--limit N] [--out 文件]
    python unpack.py mats   -s <路径>                     材质 -> shader
    python unpack.py export 输出目录 [-s 路径] [-t 类型] [-k 关键字] [--overwrite]
    python unpack.py zip    输出zip  -d 目录 [--to-desktop] [--fast] [--store]

选项:
    -s 资源路径: 单文件 / *_Data 目录 / 内含 bundle 的目录
    -t 对象类型: 逗号分隔. Texture2D(默认)/Sprite/AudioClip/TextAsset/Mesh/Shader
    -k 资源名关键字(不区分大小写)
    --limit  list 最多打印多少条(默认 300, 0=不限)

加密:
    非 UnityFS/UnityWeb/UnityRaw 魔数或解析出 0 个对象 => 提示但**不爆破**.
    已知密钥: --key <十六进制或字符串>
    明确要硬解: --brute (慢, 不建议)
"""
import argparse
import os
import sys
import time
import zipfile

if os.name == "nt":
    try:
        os.system("chcp 65001 >nul 2>&1")
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

import UnityPy

MAGICS = (b"UnityFS", b"UnityWeb", b"UnityRaw", b"UnityArchive")
TEXT_EXT = (".json", ".txt", ".xml", ".csv", ".bytes", ".yaml", ".html", ".lua")


def human(n):
    n = float(n)
    for u in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or u == "TB":
            return f"{n:.1f}{u}"
        n /= 1024


def detect(path):
    with open(path, "rb") as f:
        head = f.read(32)
    return any(head.startswith(m) for m in MAGICS), head


def resolve_src(src):
    """目录 -> 选最大的 bundle 文件; 文件 -> 原样"""
    if not os.path.isdir(src):
        return src
    cands = []
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            low = f.lower()
            if low.endswith((".unity3d", ".bundle", ".assets", ".ab", ".bin")) or "bundle" in low:
                try:
                    cands.append((os.path.getsize(p), p))
                except OSError:
                    pass
    if not cands:
        sys.exit("目录里没找到可识别的 bundle 文件: " + src)
    cands.sort(reverse=True)
    if len(cands) > 1:
        print(f"目录里有 {len(cands)} 个候选, 取最大的: {os.path.basename(cands[0][1])}")
    return cands[0][1]


def load(src, key=None, brute=False):
    path = resolve_src(src)
    if not os.path.exists(path):
        sys.exit("路径不存在: " + path)
    if os.path.isfile(path):
        ok, head = detect(path)
        if not ok:
            print("!! 文件头不是 UnityFS/UnityWeb/UnityRaw:", head[:16])
            print("!! 可能是加密的 UnityCN 包, 或不是 Unity 资源文件")
            if key:
                from UnityPy.helpers import ArchiveStorageManager as A
                A.set_assetbundle_decrypt_key(key)
                print("!! 已应用你提供的密钥")
            elif brute:
                print("!! --brute: 尝试爆破密钥(仅 UnityCN 系有意义) ...")
                from UnityPy.helpers import ArchiveStorageManager as A
                A.brute_force_key(path, b"", b"", verbose=True)
            else:
                print("!! 未提供密钥。原文件不会被修改, 只是可能解不开。")
                print("!! 要处理: --key <密钥>; 确认 UnityCN 再考虑 --brute")
    print("加载:", path)
    t0 = time.time()
    try:
        env = UnityPy.load(path)
    except Exception as e:
        print("!! 解析失败:", type(e).__name__, e)
        print("!! 通常意味着: 加密 / 压缩方式不支持 / 不是 Unity 资源。原文件未修改。")
        sys.exit(2)
    print(f"加载完成 {time.time()-t0:.1f}s, 对象 {len(env.objects)} 个")
    return env


def cmd_info(args):
    src = resolve_src(args.src)
    if os.path.isdir(args.src):
        files = sorted(os.listdir(args.src))
        print("目录:", args.src, "条目:", len(files))
        for f in files[:20]:
            p = os.path.join(args.src, f)
            if not os.path.isfile(p):
                continue
            ok, head = detect(p)
            print(f"  {f:48} {human(os.path.getsize(p)):>9}  {'明文' if ok else '非UnityFS ' + repr(head[:8])}")
        return

    ok, head = detect(src)
    print(f"文件: {src}")
    print(f"大小: {human(os.path.getsize(src))}")
    print(f"文件头: {head[:16]!r}  ->  {'明文 Unity 包' if ok else '可疑/加密'}")
    env = load(src, args.key, args.brute)
    from collections import Counter
    c = Counter()
    for obj in env.objects:
        c[obj.type.name] += 1
    print("\n对象类型统计:")
    for k, v in c.most_common(30):
        print(f"  {k:18} {v}")
    total = sum(c.values())
    print("\n资源总数:", total)
    if total == 0:
        print("!! 解析出 0 个对象: 多半是加密包, 或该文件是索引/占位")
        print("!! 不自动爆破; 有密钥用 --key, 确认 UnityCN 再考虑 --brute")


def collect(env, types, keyword, limit=0):
    """用 peek_name 预筛, 避免为过滤而反序列化整个对象"""
    kw = (keyword or "").lower()
    rows = []
    for obj in env.objects:
        tn = obj.type.name
        if types and tn not in types:
            continue
        name = None
        try:
            name = obj.peek_name()
        except Exception:
            name = None
        if kw:
            if name is None:
                try:
                    name = obj.read().m_Name
                except Exception:
                    continue
            if kw not in name.lower():
                continue
        rows.append((tn, name or "?", obj))
        if limit and len(rows) >= limit:
            break
    return rows


def cmd_list(args):
    env = load(args.src, args.key, args.brute)
    from collections import Counter
    c = Counter()
    for obj in env.objects:
        c[obj.type.name] += 1
    print("类型统计:")
    for k, v in c.most_common(30):
        print(f"  {k:18} {v}")

    rows = collect(env, args.filter_types, args.keyword, 0)
    shown = rows if not args.limit else rows[:args.limit]
    lines = [f"{t:16} {n}" for t, n, _ in sorted(shown)]
    print(f"\n资源名 ({len(rows)} 条, 显示 {len(lines)}):")
    for l in lines:
        print("  " + l)
    if args.out:
        with open(args.out, "w", encoding="utf8") as f:
            f.write("\n".join(f"{t}\t{n}" for t, n, _ in rows))
        print("已写出:", args.out)


def cmd_mats(args):
    env = load(args.src, args.key, args.brute)
    for obj in env.objects:
        if obj.type.name != "Material":
            continue
        try:
            d = obj.read()
        except Exception:
            continue
        shn = "?"
        try:
            sh = d.m_Shader.read()
            try:
                shn = sh.m_ParsedForm.m_Name
            except Exception:
                shn = getattr(sh, "m_Name", "?")
        except Exception:
            pass
        print(f"{shn:38} {d.m_Name}")


def safe_name(s):
    bad = '<>:"/\\|?*'
    s = "".join("_" if c in bad else c for c in (s or "unnamed"))
    return s[:80]


def do_export(env, outdir, types, keyword, overwrite=False):
    os.makedirs(outdir, exist_ok=True)
    kw = (keyword or "").lower()
    ok = fail = skip = 0
    seen = {}
    t0 = time.time()
    for obj in env.objects:
        tn = obj.type.name
        if types and tn not in types:
            continue
        name = None
        try:
            name = obj.peek_name()
        except Exception:
            pass
        if kw:
            if name is None:
                try:
                    name = obj.read().m_Name
                except Exception:
                    fail += 1
                    continue
            if kw not in name.lower():
                skip += 1
                continue
        try:
            d = obj.read()
        except Exception:
            fail += 1
            continue
        name = getattr(d, "m_Name", None) or name or "unnamed"
        seen[name] = seen.get(name, 0) + 1
        base = os.path.join(outdir, safe_name(name if seen[name] == 1 else f"{name}_{seen[name]}"))
        try:
            wrote = []
            if tn in ("Texture2D", "Sprite"):
                p = base + ".png"
                if not (os.path.exists(p) and not overwrite):
                    d.image.save(p)
                    wrote.append(p)
            elif tn == "AudioClip":
                try:
                    samples = d.samples or {}
                except Exception as e:
                    skip += 1
                    if skip <= 3:
                        print(f"跳过音频 {name}: 该格式 UnityPy 不支持({type(e).__name__})")
                    continue
                for sname, data in samples.items():
                    p = f"{base}_{safe_name(sname) if sname else 'audio'}.wav"
                    if os.path.exists(p) and not overwrite:
                        continue
                    with open(p, "wb") as f:
                        f.write(data)
                    wrote.append(p)
            elif tn == "TextAsset":
                data = getattr(d, "m_Script", None)
                if isinstance(data, str):
                    data = data.encode("utf8")
                if not data:
                    skip += 1
                    continue
                ext = ".txt"
                for e in TEXT_EXT:
                    if name.lower().endswith(e):
                        ext = e
                        break
                p = base + ext
                if not (os.path.exists(p) and not overwrite):
                    with open(p, "wb") as f:
                        f.write(data)
                    wrote.append(p)
            elif tn == "Mesh":
                try:
                    from UnityPy.export import MeshExporter
                    txt = MeshExporter(obj).export()
                except Exception:
                    txt = None
                if not txt:
                    skip += 1
                    continue
                p = base + ".obj"
                if not (os.path.exists(p) and not overwrite):
                    with open(p, "w", encoding="utf8") as f:
                        f.write(txt)
                    wrote.append(p)
            elif tn == "Shader":
                data = getattr(d, "m_Script", None)
                if isinstance(data, str):
                    data = data.encode("utf8")
                if not data:
                    skip += 1
                    continue
                p = base + ".shader"
                if not (os.path.exists(p) and not overwrite):
                    with open(p, "wb") as f:
                        f.write(data)
                    wrote.append(p)
            else:
                skip += 1
                continue
            if wrote:
                ok += 1
            else:
                skip += 1
            if ok and ok % 100 == 0:
                el = time.time() - t0
                print(f"已导出 {ok} ({ok/el:.1f}/s)", flush=True)
        except Exception as e:
            fail += 1
            if fail <= 5:
                print("失败:", name, e, flush=True)
    el = time.time() - t0
    print(f"完成: 成功 {ok}, 跳过 {skip}, 失败 {fail}, 耗时 {el:.1f}s")
    print("输出目录:", outdir)


def cmd_export(args):
    env = load(args.src, args.key, args.brute)
    do_export(env, args.out, args.filter_types, args.keyword, args.overwrite)


def parse_types(s):
    return ["Texture2D"] if not s else [x.strip() for x in s.split(",") if x.strip()]


def dir_size(p):
    t = 0
    for root, _, files in os.walk(p):
        for f in files:
            t += os.path.getsize(os.path.join(root, f))
    return t


def check_space(path, need):
    import shutil
    d = os.path.dirname(os.path.abspath(path)) or "."
    free = shutil.disk_usage(d).free
    if free < need:
        print(f"!! 空间不足: 需要 {human(need)}, 可用 {human(free)}")
        return False
    print(f"空间检查: 需要 {human(need)}, 可用 {human(free)} -> OK")
    return True


def make_zip(src_dir, zip_path, level=6):
    if not os.path.isdir(src_dir):
        sys.exit("目录不存在: " + src_dir)
    size = dir_size(src_dir)
    if not check_space(zip_path, int(size * 1.05)):
        return False
    os.makedirs(os.path.dirname(os.path.abspath(zip_path)), exist_ok=True)
    mode = zipfile.ZIP_STORED if level == 0 else zipfile.ZIP_DEFLATED
    n = 0
    t0 = time.time()
    with zipfile.ZipFile(zip_path, "w", mode, compresslevel=level) as z:
        for root, _, files in os.walk(src_dir):
            for f in files:
                p = os.path.join(root, f)
                z.write(p, os.path.relpath(p, src_dir))
                n += 1
                if n % 200 == 0:
                    print("打包", n, flush=True)
    print(f"压缩完成: {n} 个文件 -> {zip_path} ({human(os.path.getsize(zip_path))}), 耗时 {time.time()-t0:.1f}s")
    return True


def desktop():
    for c in (os.path.join(os.path.expanduser("~"), "Desktop"),
              os.path.join(os.path.expanduser("~"), "OneDrive", "Desktop")):
        if os.path.isdir(c):
            return c
    return os.path.expanduser("~")


def cmd_zip(args):
    out = args.outzip
    if args.to_desktop and not os.path.isabs(out):
        out = os.path.join(desktop(), out)
    level = 0 if args.store else (1 if args.fast else 6)
    make_zip(args.dir, out, level)


def main():
    ap = argparse.ArgumentParser(description="通用 Unity 解包工具")
    sub = ap.add_subparsers(dest="cmd")

    def common(p, src_required=False):
        p.add_argument("-s", "--src", required=src_required)
        p.add_argument("--key", default=None)
        p.add_argument("--brute", action="store_true")
        p.add_argument("-t", "--type", default=None)
        p.add_argument("-k", "--keyword", default=None)

    p = sub.add_parser("info"); common(p, True); p.set_defaults(func=cmd_info)
    p = sub.add_parser("list"); common(p, True)
    p.add_argument("--limit", type=int, default=300)
    p.add_argument("--out", default=None)
    p.set_defaults(func=cmd_list)
    p = sub.add_parser("mats"); common(p, True); p.set_defaults(func=cmd_mats)
    p = sub.add_parser("export"); p.add_argument("out"); common(p)
    p.add_argument("--overwrite", action="store_true"); p.set_defaults(func=cmd_export)
    p = sub.add_parser("zip"); p.add_argument("outzip"); p.add_argument("-d", "--dir", required=True)
    p.add_argument("--to-desktop", action="store_true")
    p.add_argument("--fast", action="store_true", help="低压缩率, 更快")
    p.add_argument("--store", action="store_true", help="不压缩(最快)")
    p.set_defaults(func=cmd_zip)

    args = ap.parse_args()
    if not getattr(args, "func", None):
        ap.print_help(); return
    if getattr(args, "cmd", "") != "zip":
        args.filter_types = parse_types(getattr(args, "type", None))
    args.func(args)


if __name__ == "__main__":
    main()
