#!/usr/bin/env python3
"""Build docs/api.html from the checked-in interfaces.

Every package's pkg.generated.mbti supplies the public surface; the /// blocks
in its .mbt sources supply the prose. The output is deterministic so the docs
workflow can regenerate it and fail on a diff.
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "docs" / "api.html"

PACKAGES = [
    ("wire", "Tags, varints, fixed-width numbers, length-delimited values and groups."),
    ("reflect", "Value, Message, the descriptor records and the global registries."),
    ("proto", "Binary encoding and decoding, size, merge, clone, equal, reset."),
    ("json", "The JSON mapping, including the well-known type forms."),
    ("text", "The text format: fields, groups, lists and every literal."),
    ("delim", "Varint size-delimited messages over a byte source."),
    ("dynamic", "Messages, enums and extensions built from descriptors at run time."),
    ("desc", "Building runtime descriptors, and converting them back."),
    ("parser", "The .proto language: proto2, proto3 and editions."),
    ("gen", "The protoc plugin protocol and the MoonBit code generator."),
    ("known", "The well-known types, generated from the schemas protobuf ships."),
    ("conformance", "The conformance protocol: read one format, write another."),
]

DECL = re.compile(
    r"^\s*(?:pub\(all\)\s+|pub\(open\)\s+|pub\s+)?(struct|enum|suberror|trait|fn|let)\s+"
    r"([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)"
)


def doc_comments(pkg_dir: Path) -> dict[str, str]:
    """Map an identifier to the /// block written above its declaration."""
    docs: dict[str, str] = {}
    for path in sorted(pkg_dir.glob("*.mbt")):
        text = path.read_text(encoding="utf-8").splitlines()
        block: list[str] = []
        for line in text:
            stripped = line.strip()
            if stripped.startswith("///"):
                text = stripped[3:].strip()
                # `///|` is the block marker MoonBit asks for; it is not prose.
                if text.startswith("|"):
                    text = text[1:].strip()
                block.append(text)
                continue
            if block:
                match = DECL.match(line)
                if match:
                    name = match.group(2).split("::")[-1]
                    prose = " ".join(part for part in block if part)
                    docs.setdefault(name, prose)
                block = []
    return docs


def parse_mbti(path: Path) -> list[dict]:
    """Read the declarations the interface file lists."""
    symbols: list[dict] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        match = re.match(
            r"^pub(?:\(all\)|\(open\))?\s+(fn|let|const|struct|enum|suberror|trait)(\[[^\]]*\])?\s+"
            r"([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)",
            line,
        )
        if not match:
            i += 1
            continue
        kind, _generics, name = match.group(1), match.group(2), match.group(3)
        if kind in ("struct", "enum", "suberror", "trait"):
            body: list[str] = []
            depth = line.count("{") - line.count("}")
            while depth > 0 and i + 1 < len(lines):
                i += 1
                body.append(lines[i])
                depth += lines[i].count("{") - lines[i].count("}")
            symbols.append({"kind": kind, "name": name, "sig": line.strip(), "body": [b for b in body if b.strip() != "}"]})
        else:
            symbols.append({"kind": kind, "name": name, "sig": line.strip(), "body": []})
        i += 1
    return symbols


def kind_of(symbol: dict) -> str:
    sig = symbol["sig"]
    for word in ("struct", "enum", "suberror", "trait", "fn", "let", "const"):
        if f" {word} " in sig:
            return word
    return symbol["kind"]


def render_symbol(symbol: dict, docs: dict[str, str]) -> str:
    kind = kind_of(symbol)
    name = html.escape(symbol["name"])
    doc = docs.get(symbol["name"].split("::")[-1], "")
    sig = html.escape(symbol["sig"].rstrip("{").strip())
    body = "".join("<div>" + html.escape(line.strip()) + "</div>" for line in symbol["body"][:14])
    doc_html = f"<p>{html.escape(doc)}</p>" if doc else ""
    summary = doc.split(". ")[0]
    if len(summary) > 96:
        summary = summary[:93].rstrip() + "…"
    hint = f'<span class="sdoc">{html.escape(summary)}</span>' if summary else ""
    return f"""      <details class="sym">
        <summary><span class="kind {kind}">{kind}</span><span class="sname">{name}</span>{hint}</summary>
        <div class="sym-body">
          {doc_html}<pre class="sig">{sig}</pre>{body}
        </div>
      </details>"""


CHROME = """<header class="chrome">
  <div class="chrome-in">
    <a class="brand" href="index.html" aria-label="moonproto home">
      <svg viewBox="0 0 28 28" aria-hidden="true"><path d="M9.5 4.5H5v19h4.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="square"/><path d="M18.5 4.5H23v19h-4.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="square"/><rect x="11.4" y="11.4" width="5.2" height="5.2" rx="1" fill="currentColor"/></svg>
      moonproto
    </a>
    <nav class="nav" aria-label="Sections">
      <a href="guide.html">Guide</a>
      <a href="api.html" aria-current="page">API</a>
      <a href="playground.html">Playground</a>
    </nav>
    <div class="chrome-links">
      <a class="pill-link" href="https://protobuf.dev" aria-label="Protocol Buffers specification">
        <svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M3.5 2.2h6l3 3v8.6h-9z"/><path d="M9.5 2.2v3h3"/><path d="M5.6 8.4h4.8M5.6 10.6h4.8"/></svg>
        <span>Spec</span>
      </a>
      <a class="pill-link" href="https://github.com/moonbitstack/moonproto" aria-label="moonproto on GitHub">
        <svg viewBox="0 0 16 16" aria-hidden="true" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.4 7.4 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>
        <span>GitHub</span>
      </a>
      <button class="theme-toggle" type="button" data-theme-toggle aria-label="Switch colour theme">
        <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.3"><circle cx="8" cy="8" r="3.2"/><path d="M8 1v1.6M8 13.4V15M1 8h1.6M13.4 8H15M3.05 3.05l1.13 1.13M11.82 11.82l1.13 1.13M12.95 3.05l-1.13 1.13M4.18 11.82l-1.13 1.13"/></svg>
      </button>
    </div>
  </div>
</header>"""

FOOTER = """<footer class="site">
  <div class="wrap foot">
    <div>
      <a class="brand" href="index.html">
        <svg viewBox="0 0 28 28" aria-hidden="true"><path d="M9.5 4.5H5v19h4.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="square"/><path d="M18.5 4.5H23v19h-4.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="square"/><rect x="11.4" y="11.4" width="5.2" height="5.2" rx="1" fill="currentColor"/></svg>
        moonproto
      </a>
      <p>Protocol Buffers for MoonBit. Apache-2.0.</p>
    </div>
    <div class="foot-links">
      <div class="foot-col">
        <b>Docs</b>
        <a href="guide.html">Guide</a>
        <a href="api.html">API reference</a>
        <a href="playground.html">Playground</a>
      </div>
      <div class="foot-col">
        <b>Elsewhere</b>
        <a href="https://github.com/moonbitstack/moonproto">GitHub</a>
        <a href="https://mooncakes.io/docs/moonbitstack/moonproto">MoonCakes</a>
        <a href="https://protobuf.dev">Specification</a>
      </div>
      <div class="foot-col">
        <b>Use</b>
        <a href="guide.html#install">Install</a>
        <a href="guide.html#generate">Generate code</a>
        <a href="https://github.com/moonbitstack/moonproto/blob/main/docs/skills/moonproto/SKILL.md">Agent skill</a>
      </div>
    </div>
  </div>
</footer>"""


def build() -> str:
    rail: list[str] = []
    sections: list[str] = []
    for name, summary in PACKAGES:
        pkg_dir = SRC / name
        mbti = pkg_dir / "pkg.generated.mbti"
        if not mbti.exists():
            continue
        docs = doc_comments(pkg_dir)
        symbols = parse_mbti(mbti)
        order = {"struct": 0, "enum": 1, "suberror": 2, "trait": 3, "fn": 4, "let": 5, "const": 6}
        symbols.sort(key=lambda s: (order.get(kind_of(s), 9), s["name"]))
        rendered = "\n".join(render_symbol(s, docs) for s in symbols)
        count = len(symbols)
        rail.append(f'      <a href="#pkg-{name}"><span class="n">{count}</span> {name}</a>')
        sections.append(
            f"""    <section id="pkg-{name}">
      <div class="pkg-title"><h1>{name}</h1></div>
      <p class="pkg-path">moonbitstack/moonproto/{name}</p>
      <p style="color: var(--ink-2); max-width: 62ch; margin: 0 0 24px">{html.escape(summary)}</p>
{rendered}
    </section>"""
        )

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API reference — moonproto</title>
<meta name="description" content="Every public type, value and function in moonproto, grouped by package.">
<link rel="icon" href="assets/mark.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;1,6..72,400&family=Space+Grotesk:wght@400;500;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/site.css">
</head>
<body>

{CHROME}

<div class="wrap api">
  <aside class="rail" aria-label="Packages">
    <div class="rail-group">
      <b>Packages</b>
{chr(10).join(rail)}
    </div>
    <div class="rail-group">
      <b>Also</b>
      <a href="guide.html">Guide</a>
      <a href="playground.html">Playground</a>
    </div>
  </aside>

  <main>
{chr(10).join(sections)}
  </main>
</div>

{FOOTER}

<script src="assets/site.js"></script>
</body>
</html>
"""


def main() -> int:
    page = build()
    OUT.write_text(page, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(page.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
