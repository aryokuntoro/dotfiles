#!/usr/bin/env python3
"""
icon_cheatsheet.py — Generate TSV + HTML icon cheat sheet dari font terinstal.

Usage:
    python3 icon_cheatsheet.py
    python3 icon_cheatsheet.py -f /path/to/font.ttf
    python3 icon_cheatsheet.py -o ~/cheatsheets
"""

import argparse
import json
import os
import subprocess
import sys

# ── Detect fonts via fc-list ──────────────────────────────
def find_fonts():
    """Cari font Nerd Fonts & Font Awesome pakai fc-list."""
    try:
        r = subprocess.run(
            ["fc-list", "--format=%{file}|%{family[0]}\n"],
            capture_output=True, text=True, timeout=10,
        )
    except FileNotFoundError:
        print("Error: fc-list tidak ada. Install: sudo pacman -S fontconfig")
        sys.exit(1)

    keywords = ["nerd", "font awesome", "fontawesome",
                "fa-solid", "fa-regular", "fa-brands"]
    results = []
    seen = set()

    for line in r.stdout.strip().split("\n"):
        if "|" not in line:
            continue
        path, family = line.split("|", 1)
        path = path.strip()
        family = family.strip()
        combined = (path + " " + family).lower()
        if any(k in combined for k in keywords) and path not in seen:
            seen.add(path)
            results.append((path, family))
            print(f"  Found: {family}")
            print(f"    -> {path}")

    return results


# ── Extract glyphs ───────────────────────────────────────
def extract_glyphs(font_path, font_family):
    """Extract glyph dari Private Use Area (E000–F8FF)."""
    from fontTools.ttLib import TTFont

    glyphs = []
    try:
        font = TTFont(font_path, fontNumber=0)
    except Exception as e:
        print(f"  Error opening {font_path}: {e}")
        return glyphs

    cmap = font.getBestCmap()
    if not cmap:
        font.close()
        return glyphs

    for cp, name in sorted(cmap.items()):
        if 0xE000 <= cp <= 0xF8FF and name and name not in (".notdef", ".null"):
            cat = categorize(name, cp)
            glyphs.append({
                "char": chr(cp),
                "name": name,
                "cp": f"U+{cp:04X}",
                "cp_dec": cp,
                "font": font_family,
                "cat": cat,
            })

    font.close()
    return glyphs


def categorize(name, cp):
    """Klasifikasi glyph berdasarkan nama & codepoint."""
    n = name.lower()
    if n.startswith("nf-fa-") or n.startswith("nf-fae-"):
        return "fa"
    elif n.startswith("nf-md-") or n.startswith("nf-mdi-"):
        return "mdi"
    elif n.startswith("nf-oct-"):
        return "oct"
    elif n.startswith("nf-dev-"):
        return "dev"
    elif n.startswith("nf-weather-"):
        return "weather"
    elif n.startswith("nf-cod-") or n.startswith("nf-codicon"):
        return "cod"
    elif n.startswith("nf-seti-") or n.startswith("nf-custom-"):
        return "seti"
    elif n.startswith("nf-pl-"):
        return "powerline"
    elif n.startswith("fa-") or "fontawesome" in n:
        return "fa"
    elif n.startswith("nf-"):
        return "nerd"
    elif 0xF000 <= cp <= 0xF8FF:
        return "fa"
    else:
        return "nerd"


# ── Write TSV ────────────────────────────────────────────
def write_tsv(glyphs, path):
    with open(path, "w", encoding="utf-8") as f:
        f.write("char\tname\tcodepoint\tcodepoint_dec\tcategory\tfont\n")
        for g in glyphs:
            f.write(
                f"{g['char']}\t{g['name']}\t{g['cp']}\t{g['cp_dec']}\t{g['cat']}\t{g['font']}\n"
            )
    print(f"  TSV  : {os.path.abspath(path)}")


# ── Write HTML ────────────────────────────────────────────
def write_html(glyphs, path, font_files):
    """HTML dengan @font-face file://, kategori, search, pagination."""

    # @font-face rules
    font_faces = ""
    font_families = []
    for i, (fpath, fname) in enumerate(font_files):
        fid = f"ic{i}"
        font_faces += f"  @font-face {{\n    font-family: '{fid}';\n    src: url('file://{fpath}') format('truetype');\n  }}\n"
        font_families.append(f"'{fid}'")
    font_css = ", ".join(font_families) + ", monospace"

    data_json = json.dumps(glyphs)

    html = f"""<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Icon Cheat Sheet</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ background: #1e1e2e; color: #cdd6f4; font-family: monospace; padding: 16px; }}
h1 {{ color: #89b4fa; font-size: 1.4em; margin-bottom: 8px; }}
.sub {{ color: #6c7086; font-size: 0.8em; margin-bottom: 16px; }}

{font_faces}

.glyph, .card {{ font-family: {font_css}; }}

.bar {{ display: flex; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; align-items: center; }}
.bar input {{ flex: 1; min-width: 180px; }}
input, select {{
  background: #313244; color: #cdd6f4;
  border: 1px solid #45475a; border-radius: 6px; padding: 8px 12px;
  font-size: 13px; font-family: monospace;
}}
input:focus, select:focus {{ outline: none; border-color: #89b4fa; }}
#count {{ color: #a6adc8; font-size: 0.8em; }}

.cats {{ display: flex; gap: 4px; margin-bottom: 12px; flex-wrap: wrap; }}
.cats button {{
  background: #313244; color: #a6adc8;
  border: 1px solid #45475a; border-radius: 12px;
  padding: 4px 12px; font-size: 0.75em; cursor: pointer;
  font-family: monospace; transition: all 0.15s;
}}
.cats button:hover {{ border-color: #89b4fa; color: #cdd6f4; }}
.cats button.active {{ background: #89b4fa; color: #1e1e2e; border-color: #89b4fa; }}

#grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 6px; }}
.card {{
  display: flex; align-items: center; gap: 10px;
  padding: 8px; background: #313244; border-radius: 6px;
  cursor: pointer; border: 1px solid transparent;
  transition: border-color 0.15s;
}}
.card:hover {{ border-color: #89b4fa; }}
.glyph {{ font-size: 24px; min-width: 32px; text-align: center; color: #f9e2af; }}
.info {{ flex: 1; overflow: hidden; }}
.name {{ font-size: 0.8em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
.cp {{ font-size: 0.7em; color: #6c7086; margin-top: 2px; }}
.badge {{
  display: inline-block; padding: 1px 6px; border-radius: 3px;
  font-size: 0.6em; font-weight: bold; text-transform: uppercase;
  margin-left: 4px; vertical-align: middle;
}}
.badge-fa {{ background: #f9e2af; color: #1e1e2e; }}
.badge-mdi {{ background: #cba6f7; color: #1e1e2e; }}
.badge-oct {{ background: #fab387; color: #1e1e2e; }}
.badge-dev {{ background: #a6e3a1; color: #1e1e2e; }}
.badge-weather {{ background: #89dceb; color: #1e1e2e; }}
.badge-cod {{ background: #f5c2e7; color: #1e1e2e; }}
.badge-seti {{ background: #94e2d5; color: #1e1e2e; }}
.badge-powerline {{ background: #f38ba8; color: #1e1e2e; }}
.badge-nerd {{ background: #585b70; color: #cdd6f4; }}

#pager {{ text-align: center; margin: 16px 0; display: flex; justify-content: center; align-items: center; gap: 8px; }}
#pager button {{
  background: #313244; color: #cdd6f4;
  border: 1px solid #45475a; border-radius: 6px;
  padding: 6px 16px; cursor: pointer; font-family: monospace;
}}
#pager button:hover:not(:disabled) {{ border-color: #89b4fa; }}
#pager button:disabled {{ opacity: 0.3; cursor: default; }}
#pageInfo {{ color: #a6adc8; font-size: 0.85em; min-width: 80px; }}

#toast {{
  position: fixed; bottom: 20px; left: 50%;
  transform: translateX(-50%);
  background: #a6e3a1; color: #1e1e2e;
  padding: 8px 20px; border-radius: 6px;
  font-weight: bold; display: none; z-index: 999;
}}
.empty {{ text-align: center; padding: 40px; color: #6c7086; }}
</style>
</head>
<body>

<h1>Icon Cheat Sheet</h1>
<div class="sub">Klik card untuk copy glyph &middot; {len(glyphs)} glyphs total</div>

<div class="bar">
  <input type="text" id="search" placeholder="Cari nama glyph... (mis: cpu, heart, wifi)" oninput="onFilter()">
  <select id="fontSel" onchange="onFilter()"></select>
  <span id="count"></span>
</div>

<div class="cats" id="cats"></div>

<div id="grid"></div>
<div class="empty" id="empty" style="display:none;">Tidak ada glyph cocok.</div>

<div id="pager">
  <button id="prev" onclick="changePage(-1)">&laquo; Prev</button>
  <span id="pageInfo">1 / 1</span>
  <button id="next" onclick="changePage(1)">Next &raquo;</button>
</div>

<div id="toast">Copied!</div>

<script>
const DATA = {data_json};
const PER_PAGE = 100;
let filtered = DATA;
let page = 0;
let activeCat = 'all';

// Kategori
var cats = {{}};
DATA.forEach(function(d) {{ cats[d.cat] = (cats[d.cat] || 0) + 1; }});
var catList = Object.keys(cats).sort();
var catDiv = document.getElementById('cats');
catList.forEach(function(c) {{
  catDiv.innerHTML += '<button class="cat-btn" data-cat="' + c + '" onclick="setCat(this)">' + c.toUpperCase() + ' (' + cats[c] + ')</button>';
}});

function setCat(btn) {{
  activeCat = btn.dataset.cat;
  document.querySelectorAll('.cat-btn').forEach(function(b) {{ b.classList.remove('active'); }});
  btn.classList.add('active');
  onFilter();
}}

// Font dropdown
(function() {{
  var fonts = [];
  DATA.forEach(function(d) {{ if (fonts.indexOf(d.font) === -1) fonts.push(d.font); }});
  var sel = document.getElementById('fontSel');
  sel.innerHTML = '<option value="">All Fonts</option>';
  fonts.forEach(function(f) {{
    sel.innerHTML += '<option value="' + f + '">' + f + '</option>';
  }});
}})();

function onFilter() {{
  var q = document.getElementById('search').value.toLowerCase();
  var fontF = document.getElementById('fontSel').value;
  filtered = DATA.filter(function(d) {{
    return (q === '' || d.name.toLowerCase().indexOf(q) !== -1) &&
           (fontF === '' || d.font === fontF) &&
           (activeCat === 'all' || d.cat === activeCat);
  }});
  page = 0;
  render();
}}

function render() {{
  var grid = document.getElementById('grid');
  var start = page * PER_PAGE;
  var items = filtered.slice(start, start + PER_PAGE);
  var html = '';
  items.forEach(function(d) {{
    html += '<div class="card" onclick="copyChar(this)" data-char="' + d.char + '">'
      + '<span class="glyph">' + d.char + '</span>'
      + '<div class="info">'
      + '<div class="name">' + d.name + ' <span class="badge badge-' + d.cat + '">' + d.cat + '</span></div>'
      + '<div class="cp">' + d.cp + ' &middot; ' + d.font + '</div>'
      + '</div></div>';
  }});
  grid.innerHTML = html;
  var totalPages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
  document.getElementById('pageInfo').textContent = (page + 1) + ' / ' + totalPages;
  document.getElementById('prev').disabled = page === 0;
  document.getElementById('next').disabled = page >= totalPages - 1;
  document.getElementById('count').textContent = filtered.length + ' / ' + DATA.length;
  document.getElementById('empty').style.display = filtered.length === 0 ? '' : 'none';
  document.getElementById('pager').style.display = filtered.length === 0 ? 'none' : '';
}}

function changePage(dir) {{
  var totalPages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
  page = Math.max(0, Math.min(page + dir, totalPages - 1));
  render();
  window.scrollTo(0, 0);
}}

function copyChar(card) {{
  var char = card.getAttribute('data-char');
  if (navigator.clipboard) {{
    navigator.clipboard.writeText(char).then(showToast);
  }} else {{
    var ta = document.createElement('textarea');
    ta.value = char;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
    showToast();
  }}
}}

function showToast() {{
  var t = document.getElementById('toast');
  t.style.display = 'block';
  setTimeout(function() {{ t.style.display = 'none'; }}, 1000);
}}

render();
</script>
</body>
</html>"""

    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  HTML : {os.path.abspath(path)}")


# ── Main ─────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Generate TSV + HTML icon cheat sheet")
    parser.add_argument("--font", "-f", help="Path font spesifik")
    parser.add_argument("--output", "-o", default=".", help="Direktori output")
    args = parser.parse_args()

    try:
        from fontTools.ttLib import TTFont  # noqa: F401
    except ImportError:
        print("Error: fonttools belum terinstal.")
        print("Install: pip install fonttools")
        sys.exit(1)

    output_dir = os.path.expanduser(args.output)
    os.makedirs(output_dir, exist_ok=True)

    print("=" * 50)
    print("  Icon Cheat Sheet Generator")
    print("=" * 50)

    # 1. Find fonts
    if args.font:
        fp = os.path.expanduser(args.font)
        if not os.path.isfile(fp):
            print(f"Error: {fp} tidak ditemukan")
            sys.exit(1)
        fonts = [(fp, os.path.basename(fp))]
        print(f"\n[1/3] Font manual: {fp}")
    else:
        print("\n[1/3] Mencari font dengan fc-list...")
        fonts = find_fonts()

    if not fonts:
        print("\nTidak ada font ditemukan!")
        print("Coba: fc-list | grep -iE 'nerd|fontawesome|fa-solid'")
        sys.exit(1)

    # 2. Extract glyphs
    print(f"\n[2/3] Extracting glyphs dari {len(fonts)} font...")
    all_glyphs = []
    for fp, ff in fonts:
        print(f"  {ff}...", end=" ", flush=True)
        g = extract_glyphs(fp, ff)
        print(f"{len(g)} glyphs")
        all_glyphs.extend(g)

    # Deduplicate
    seen = set()
    unique = []
    for g in all_glyphs:
        key = (g["cp"], g["name"])
        if key not in seen:
            seen.add(key)
            unique.append(g)

    print(f"\n  Total unique: {len(unique)} glyphs")

    if not unique:
        print("Tidak ada glyph di Private Use Area!")
        sys.exit(1)

    # 3. Generate output
    print(f"\n[3/3] Generate output...")
    tsv_path = os.path.join(output_dir, "icon_cheatsheet.tsv")
    html_path = os.path.join(output_dir, "icon_cheatsheet.html")
    write_tsv(unique, tsv_path)
    write_html(unique, html_path, fonts)

    print(f"\nSelesai! {len(unique)} glyphs.")
    print(f"Buka: file://{os.path.abspath(html_path)}")


if __name__ == "__main__":
    main()
