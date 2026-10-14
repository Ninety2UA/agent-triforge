"""Assemble each composition into a HyperFrames project under .work/<name>/ (git ignores .work/):
inline src/ds.css and src/ds.js, copy the site's Familjen Grotesk and the vendored GSAP next to it,
and write the project files with HyperFrames pinned. Edit src/; never edit .work/.

    python3 build.py                  # every piece
    python3 build.py film readme-hero # some pieces
"""
import json
import pathlib
import shutil
import sys

MOTION = pathlib.Path(__file__).resolve().parent
SRC = MOTION / "src"
WORK = MOTION / ".work"
FONT = MOTION.parent / "src" / "assets" / "fonts" / "FamiljenGrotesk-var.woff2"
GSAP = MOTION / "vendor" / "gsap.min.js"
HYPERFRAMES = "hyperframes@0.8.140"
NAMES = ["film", "loop-roster", "loop-lease", "loop-review", "loop-unattended", "readme-hero"]

names = sys.argv[1:] or NAMES
unknown = [n for n in names if n not in NAMES]
if unknown:
    sys.exit("build.py: unknown piece(s) %s (known: %s)" % (", ".join(unknown), ", ".join(NAMES)))

css = (SRC / "ds.css").read_text()
js = (SRC / "ds.js").read_text()
for name in names:
    out = WORK / name
    (out / "assets" / "fonts").mkdir(parents=True, exist_ok=True)
    shutil.copy2(FONT, out / "assets" / "fonts" / FONT.name)
    shutil.copy2(GSAP, out / "assets" / GSAP.name)
    html = (SRC / f"{name}.html").read_text()
    if "/*{{DS_CSS}}*/" not in html or "//{{DS_JS}}" not in html:
        sys.exit(f"build.py: src/{name}.html lacks the /*{{{{DS_CSS}}}}*/ or //{{{{DS_JS}}}} slot")
    (out / "index.html").write_text(html.replace("/*{{DS_CSS}}*/", css).replace("//{{DS_JS}}", js))
    (out / "hyperframes.json").write_text(json.dumps({
        "$schema": "https://hyperframes.heygen.com/schema/hyperframes.json",
        "registry": "https://raw.githubusercontent.com/heygen-com/hyperframes/main/registry",
        "paths": {"blocks": "compositions", "components": "compositions/components", "assets": "assets"},
        "media": {"autoProxy": True},
    }, indent=2) + "\n")
    (out / "package.json").write_text(json.dumps({
        "name": f"triforge-{name}", "private": True, "type": "module",
        "scripts": {"check": f"npx --yes {HYPERFRAMES} check", "render": f"npx --yes {HYPERFRAMES} render"},
    }, indent=2) + "\n")
    (out / "meta.json").write_text(json.dumps({"id": name, "name": name}, indent=2) + "\n")
    print("built", out.relative_to(MOTION))
