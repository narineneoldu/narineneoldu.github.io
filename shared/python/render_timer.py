#!/usr/bin/env python3
# shared/python/render_timer.py
import time, os, json, pathlib, sys, subprocess

p = pathlib.Path(".qrender_timer.tmp.json")
emit_script = pathlib.Path("../shared/python/emit_render_json.py")

if len(sys.argv) < 2:
    sys.exit("Usage: render_timer.py start|end")

if sys.argv[1] == "start":
    # Başlangıç zamanını kaydet
    p.write_text(json.dumps({"t": time.time()}))

elif sys.argv[1] == "end":
    # Süreyi hesapla
    t0 = json.loads(p.read_text())["t"]
    dur = time.time() - t0

    try:
        subprocess.run(
            [sys.executable, str(emit_script)],
            check=True
        )
    except subprocess.CalledProcessError as e:
        print(f"⚠️  emit_render_json.py hata verdi: {e}")
    except FileNotFoundError:
        print("⚠️  emit_render_json.py bulunamadı")

    # Sadece toplam geçen süreyi yazdır
    print(f"✅  Total elapsed time : \033[36m{dur:.3f} s\033[0m\n")

    # --- JSON dosyasını sil ---
    try:
        p.unlink()        # dosyayı sil
    except FileNotFoundError:
        pass
