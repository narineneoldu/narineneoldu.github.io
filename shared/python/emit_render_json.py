#!/usr/bin/env python3
# shared/python/emit_render_json.py
import os, json
from collections import OrderedDict

def to_posix(path: str) -> str:
    return path.replace("\\", "/")

def find_tmp_files(lang_code: str, root: str):
    needle = f".qrender-time.tmp-{lang_code}.tsv"
    found = []
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if name == needle:
                path = os.path.join(dirpath, name)
                try:
                    mtime = os.path.getmtime(path)
                except OSError:
                    mtime = 0.0
                found.append((path, mtime))
    found.sort(key=lambda x: x[1])  # last write wins
    return found

def parent_dirs_no_root(relpath: str):
    """Yield all parent folders (posix) except root.
       'a/b/c.qmd' -> ['a', 'a/b']"""
    relpath = relpath.strip("/")
    parts = relpath.split("/") if relpath else []
    if not parts:
        return
    # drop filename
    parts = parts[:-1]
    cur = []
    for p in parts:
        cur.append(p)
        yield "/".join(cur)

def build(lang_code: str, project_root: str = ".") -> None:
    tmp_files = find_tmp_files(lang_code, project_root)

    if not tmp_files:
        return

    if len(tmp_files) < 2:
        return

    # ---- read per-file ms (root-relative posix paths) ----
    files = {}  # { "dir/file.qmd": ms }
    for path, _ in tmp_files:
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split("\t", 1)
                    if len(parts) != 2:
                        continue
                    relpath, ms_str = parts
                    try:
                        ms = float(ms_str)
                    except ValueError:
                        continue
                    files[to_posix(relpath)] = ms  # overwrite on duplicates
        except OSError:
            continue

    # ---- sort files deterministically ----
    files_sorted = OrderedDict(
        sorted(((k, round(v, 3)) for k, v in files.items()), key=lambda kv: kv[0])
    )

    # ---- folders aggregate (recursive), WITHOUT root "/" ----
    folders = {}
    for relpath, ms in files_sorted.items():
        for folder in parent_dirs_no_root(relpath):
            folders[folder] = folders.get(folder, 0.0) + ms

    folders_sorted = OrderedDict(
        sorted(((k, round(v, 3)) for k, v in folders.items()), key=lambda kv: kv[0])
    )

    total_ms = round(sum(files_sorted.values()), 3)
    count = len(files_sorted)
    max_length = max((len(k) for k in files_sorted.keys()), default=0)
    
    out_path = os.path.join(project_root, f".qrender-time-{lang_code}.json")
    data = {
        "files": files_sorted,      # aynı kaldı
        "folders": folders_sorted,  # yeni: root hariç klasör toplamları
        "total": total_ms,
        "count": count,
        "max-length": max_length    # yeni: en uzun yol karakter sayısı
    }

    print(f"\n⚙️  Quarto render time : \033[36m{total_ms/1000.0:.3f} sec\033[0m")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # cleanup tmp files
    for path, _ in tmp_files:
        try: os.remove(path)
        except OSError: pass

def main():
    project_root = os.getenv("QUARTO_PROJECT_DIR", ".")
    for code in ("tr", "en"):
        build(code, project_root)

if __name__ == "__main__":
    main()
