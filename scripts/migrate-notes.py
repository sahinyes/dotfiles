#!/usr/bin/env python3
"""Convert the old Sublime outline notes (*.yaml, not real YAML) to Markdown.

A one-off migration. It never changes the old files and never overwrites a
file: the Markdown goes into a new --out directory.

    old=(~/Documents/notes.yaml ~/Desktop/notes.yaml ~/Documents/sublime-docs/*.yaml)
    scripts/migrate-notes.py --dry-run --out ~/notes "${old[@]}"
    scripts/migrate-notes.py --out ~/notes "${old[@]}"

Rules (target format: docs/NOTES-CONVENTION.md):
    -* text   ->  - [!] text   important
    +  text   ->  - [x] text   done
    -  text   ->  - [ ] text   open task (--dash-as-note keeps "- text")
    -text     ->  - [ ] text   a dash glued to a word: the space was forgotten
    key:      ->  ## key       a "...:" line of at most 60 characters at column 0
        key:  ->  - **key**    the same line when indented
    -----     ->  ---          a line of 2+ dashes; a blank line goes before it,
                               so the line above never turns into a heading
     text     ->  1-3 spaces and no marker: joined to the line above
Indentation: a tab counts as 4 columns (tabs + spaces/4); each nesting level
becomes 2 spaces and a child is at most one level deeper than its parent.
Trailing spaces, repeated blank lines and items without text are dropped.
Every file gets YAML front matter (title, project, tags: [migrated], date).
File names are slugs (reading list.yaml -> reading-list.md); files with the
same name get their folder added (notes-documents.md, notes-desktop.md).

Safety net: per file, the number of each marker must be the same before and
after, and the text of every source line must appear in the output in the
same order. A file that fails is not written and the exit code is 1.
Exit code 2 means nothing was written (bad arguments or a refusal).
"""

import argparse
import datetime
import difflib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

TAB = 4  # Sublime's default tab width
KEY_MAX = 60  # a longer line ending in ':' is a sentence, not a heading

# "-*" important, "+ " done, "- " open. A dash glued to a letter ("-word") is
# an item whose space was forgotten; "--x", "-1", "->" and "+41" stay text.
MARKER = re.compile(r"-\*|\+(?=\s|$)|-(?=\s|$)|-(?=[^\W\d_])")
SEPARATOR = re.compile(r"-{2,}")
TASK = {"-*": "- [!] ", "+": "- [x] ", "-": "- [ ] "}
MARKER_NAMES = {"-*": "-* -> [!]", "+": "+ -> [x]", "-": "- -> [ ]"}

# Counted on the output, independently of the converter.
OUTPUT_MARKERS = {
    "-*": re.compile(r"\s*- \[!\]( |$)"),
    "+": re.compile(r"\s*- \[x\]( |$)"),
    "-": re.compile(r"\s*- \[ \]( |$)"),
    "plain": re.compile(r"\s*- (?!\[[ x!]\]( |$))"),
}
# Leading Markdown structure, removed before the text-preservation check.
STRUCTURE = re.compile(r"\s*(- \[[ x!]\] |## |- \*\*|- )?")
# Plain text that Markdown would read as a block of its own.
MD_BLOCK = re.compile(r"[#>|<]|```|~~~|\d+[.)](\s|$)")
INNER_ITEM = re.compile(r"\t(-\*|[-+])\s")
YAML_WORDS = {"true", "false", "yes", "no", "on", "off", "null"}


class MigrationError(Exception):
    """The converted file failed a safety check; it must not be written."""


class UsageError(Exception):
    """Bad arguments or a refusal; nothing is written."""


@dataclass
class Line:
    num: int  # 1-based source line number
    kind: str  # blank, sep, item, key or text
    col: int = 0  # visual column of the first character
    marker: str = ""  # "-*", "+" or "-" for items
    text: str = ""  # content without indent, marker, trailing blanks (key: no colon)
    cont: bool = False  # 1-3 spaces and no marker: a wrapped line
    nospace: bool = False  # "-word"


@dataclass
class Result:
    markdown: str
    lines: list
    before: dict
    after: dict
    stats: dict
    indent: str
    review: list = field(default_factory=list)  # (line number, reason)


def column(lead):
    col = 0
    for ch in lead:
        col = (col // TAB + 1) * TAB if ch == "\t" else col + 1
    return col


def classify(num, raw):
    rest = raw.lstrip(" \t")
    lead = raw[: len(raw) - len(rest)]
    body = rest.rstrip()
    if not body:
        return Line(num, "blank")
    col = column(lead)
    if SEPARATOR.fullmatch(body):
        return Line(num, "sep", col)
    m = MARKER.match(body)
    if m:
        nospace = (
            m.group() == "-" and m.end() < len(body) and not body[m.end()].isspace()
        )
        return Line(
            num, "item", col, m.group(), body[m.end() :].strip(), nospace=nospace
        )
    cont = 0 < len(lead) < TAB and lead == " " * len(lead)
    key = body[:-1].rstrip()
    if body.endswith(":") and 0 < len(key) <= KEY_MAX:
        return Line(num, "key", col, text=key, cont=cont)
    return Line(num, "text", col, text=body, cont=cont)


def split_lines(text):
    text = text.removeprefix("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    return lines


def indent_style(raw_lines):
    leads = {
        ch
        for raw in raw_lines
        if raw.strip()
        for ch in raw[: len(raw) - len(raw.lstrip(" \t"))]
    }
    return {frozenset(): "none", frozenset("\t"): "tabs", frozenset(" "): "spaces"}.get(
        frozenset(leads), "tabs+spaces"
    )


def review_reasons(ln):
    if ln.nospace:
        yield 'no space after "-", read as a task'
    if ln.kind == "item" and ln.marker == "-" and ln.text.startswith("*"):
        yield 'task text starts with "*" (only "-*" means important)'
    if ln.kind == "item" and ln.text.endswith(":"):
        yield 'task ends with ":" (was it a heading?)'
    if ln.kind == "text" and ln.text.endswith(":"):
        yield f'line ending with ":" is longer than {KEY_MAX} characters, kept as text'
    if ln.kind == "text" and ln.text.startswith("--"):
        yield 'line starts with "--", kept as text'
    if ln.kind == "text" and MD_BLOCK.match(ln.text):
        yield "text starts with Markdown syntax, check how it renders"
    if INNER_ITEM.search(ln.text):
        yield "a second item after a tab on the same line"


def convert(lines, dash_as_note=False):
    """Turn classified lines into Markdown body lines. Returns (body, stats, review)."""
    out, review = [], []
    stats = {"headings": 0, "subkeys": 0, "separators": 0, "joined": 0, "dropped": 0}
    stack = []  # (column, is_item) of the lines the next line may nest under
    prev = "blank"  # kind of the previous source line
    # Item depth of the paragraph the next line would continue (-1: top level,
    # None: no open paragraph). Markdown glues a less indented text line onto
    # that paragraph ("lazy continuation"), so such a line gets a blank first.
    para = None

    def blank():
        nonlocal para
        para = None
        if out and out[-1]:
            out.append("")

    for ln in lines:
        review += [(ln.num, why) for why in review_reasons(ln)]
        if ln.kind == "blank":
            blank()
            prev = "blank"
            continue
        if ln.cont and prev in ("item", "text"):
            out[-1] += " " + ln.text + (":" if ln.kind == "key" else "")
            stats["joined"] += 1
            review.append((ln.num, "wrapped line joined to the line above"))
            continue
        if ln.kind == "sep":
            blank()
            out += ["---", ""]
            stack.clear()
            stats["separators"] += 1
            prev = "sep"
            continue
        if ln.kind == "key" and ln.col == 0:
            blank()
            out += ["## " + ln.text, ""]
            stack.clear()
            stats["headings"] += 1
            prev = "heading"
            continue
        if ln.kind == "item" and not ln.text:
            stats["dropped"] += 1
            review.append((ln.num, "item without text dropped"))
            prev = "dropped"
            continue

        while stack and stack[-1][0] >= ln.col:
            stack.pop()
        depth = sum(is_item for _, is_item in stack)
        pad = "  " * depth
        if ln.kind == "item":
            prefix = "- " if dash_as_note and ln.marker == "-" else TASK[ln.marker]
            out.append(pad + prefix + ln.text)
            para = depth
        elif ln.kind == "key":
            out.append(pad + "- **" + ln.text + "**")
            stats["subkeys"] += 1
            para = depth
        else:
            if para is not None and para >= depth:
                blank()
            if para is None:
                para = depth - 1
            out.append(pad + ln.text)
        stack.append((ln.col, ln.kind != "text"))
        prev = ln.kind
    while out and not out[-1]:
        out.pop()
    return out, stats, review


def count_source(lines):
    counts = {"-*": 0, "+": 0, "-": 0}
    for ln in lines:
        if ln.kind == "item" and ln.text:
            counts[ln.marker] += 1
    return counts


def count_output(body):
    return {
        name: sum(1 for x in body if rx.match(x)) for name, rx in OUTPUT_MARKERS.items()
    }


def verify(lines, body, dash_as_note, subkeys):
    """Raise MigrationError unless markers and text survived the conversion."""
    before, after = count_source(lines), count_output(body)
    want = {
        "-*": before["-*"],
        "+": before["+"],
        "-": 0 if dash_as_note else before["-"],
        "plain": subkeys + (before["-"] if dash_as_note else 0),
    }
    problems = [
        f"{MARKER_NAMES.get(k, 'plain - items')}: {want[k]} expected, {after[k]} found"
        for k in want
        if want[k] != after[k]
    ]
    # Every source text, in order, must be somewhere in the output text.
    hay = "\n".join(x[STRUCTURE.match(x).end() :] for x in body)
    pos = 0
    for ln in lines:
        if not ln.text:
            continue
        found = hay.find(ln.text, pos)
        if found < 0:
            problems.append(
                f"line {ln.num}: text missing or out of order in the output"
            )
        else:
            pos = found + len(ln.text)
    if problems:
        raise MigrationError("; ".join(problems))
    return before, after


def yaml_str(value):
    """Quote a front matter value unless YAML reads it as a plain string."""
    plain = re.fullmatch(r"[^\W\d][\w .-]*", value) and value.lower() not in YAML_WORDS
    return value if plain else json.dumps(value, ensure_ascii=False)


def migrate_text(text, title, project, date, dash_as_note=False):
    """Convert one file's text. Raises MigrationError when a check fails."""
    raw = split_lines(text)
    lines = [classify(i, x) for i, x in enumerate(raw, 1)]
    body, stats, review = convert(lines, dash_as_note)
    before, after = verify(lines, body, dash_as_note, stats["subkeys"])
    front = [
        "---",
        f"title: {yaml_str(title)}",
        f"project: {project}",
        "tags: [migrated]",
        f"date: {date}",
        "---",
    ]
    md_lines = front + ([""] + body if body else [])
    return Result(
        "\n".join(md_lines) + "\n", raw, before, after, stats, indent_style(raw), review
    )


def slugify(text):
    return re.sub(r"[\W_]+", "-", text.lower()).strip("-") or "notes"


def output_names(sources):
    """File name per source. Name clashes get the parent directory appended
    (notes-documents.md, notes-desktop.md), so the result does not depend on
    the argument order; anything still clashing gets -2, -3 in path order."""
    slugs = [slugify(p.stem) for p in sources]
    wanted = [
        f"{s}-{slugify(p.parent.name)}" if slugs.count(s) > 1 else s
        for p, s in zip(sources, slugs)
    ]
    names, used = [""] * len(sources), set()
    for i in sorted(range(len(sources)), key=lambda i: str(sources[i])):
        name, n = wanted[i], 2
        while name in used:
            name, n = f"{wanted[i]}-{n}", n + 1
        used.add(name)
        names[i] = name + ".md"
    return names


def check_sources(paths):
    sources = []
    for p in paths:
        p = p.expanduser()
        if not p.is_file():
            raise UsageError(f"{p}: not a file")
        real = p.resolve()
        if real in sources:
            raise UsageError(f"{p}: given twice")
        sources.append(real)
    return sources


def check_out(out_dir, sources, targets):
    real_out = out_dir.resolve()
    for src in sources:
        if real_out == src.parent or src.parent in real_out.parents:
            raise UsageError(
                f"--out {out_dir} is inside the source folder {src.parent}"
            )
    if out_dir.exists() and not out_dir.is_dir():
        raise UsageError(f"--out {out_dir} is not a directory")
    existing = [str(t) for t in targets if t.exists() or t.is_symlink()]
    if existing:
        raise UsageError("refusing to overwrite " + ", ".join(existing))


def iso_date(value):
    try:
        return datetime.date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError("expected YYYY-MM-DD") from None


def tilde(path):
    home = str(Path.home())
    return (
        "~" + str(path)[len(home) :] if str(path).startswith(home + "/") else str(path)
    )


def print_report(src, target, res, dash_as_note):
    b, a, s = res.before, res.after, res.stats
    dash_after = (
        f"notes {a['plain'] - s['subkeys']}" if dash_as_note else f"[ ] {a['-']}"
    )
    print(f"{tilde(src)} -> {target.name}")
    print(f"  lines {len(res.lines)}, indent {res.indent}")
    print(
        f"  markers  -* {b['-*']} -> [!] {a['-*']} | + {b['+']} -> [x] {a['+']}"
        f" | - {b['-']} -> {dash_after}"
    )
    print(
        f"  headings {s['headings']}, sub-keys {s['subkeys']},"
        f" separators {s['separators']}, joined {s['joined']}, dropped {s['dropped']}"
    )
    reasons = {}
    for num, why in res.review:
        reasons.setdefault(why, []).append(str(num))
    for why, nums in reasons.items():
        print(f"  review: {why}: line {', '.join(nums)}")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog=__doc__.split("\n\n", 1)[1],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("sources", nargs="+", type=Path, help="old outline files (*.yaml)")
    ap.add_argument(
        "--out",
        required=True,
        type=Path,
        help="directory for the Markdown files (created if missing)",
    )
    ap.add_argument(
        "--dry-run", action="store_true", help="print stats and a diff, write nothing"
    )
    ap.add_argument(
        "--dash-as-note",
        action="store_true",
        help='keep "- text" as a note instead of an open task',
    )
    ap.add_argument(
        "--date",
        type=iso_date,
        default=datetime.datetime.now().astimezone().date().isoformat(),
        help="front matter date",
    )
    ap.add_argument(
        "--project", help="front matter project (default: slug of each file name)"
    )
    args = ap.parse_args(argv)

    try:
        sources = check_sources(args.sources)
        out_dir = args.out.expanduser()
        targets = [out_dir / name for name in output_names(sources)]
        check_out(out_dir, sources, targets)
    except UsageError as err:
        print(f"migrate-notes: {err}", file=sys.stderr)
        return 2

    failed, done = 0, []
    for src, target in zip(sources, targets):
        try:
            text = src.read_bytes().decode("utf-8")
            project = slugify(args.project or src.stem)
            res = migrate_text(text, src.stem, project, args.date, args.dash_as_note)
        except (OSError, UnicodeDecodeError, MigrationError) as err:
            print(
                f"migrate-notes: {tilde(src)}: {err} (file not written)",
                file=sys.stderr,
            )
            failed += 1
            continue
        done.append((src, target, res))

    if done and not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)
    for src, target, res in done:
        print_report(src, target, res, args.dash_as_note)
        if args.dry_run:
            diff = difflib.unified_diff(
                res.lines,
                res.markdown.rstrip("\n").split("\n"),
                tilde(src),
                tilde(target),
                lineterm="",
            )
            print("\n".join(diff))
        else:
            # Mode "x" fails if the file appeared since the check: never overwrite.
            with open(target, "x", encoding="utf-8", newline="\n") as f:
                f.write(res.markdown)
    if args.dry_run:
        print("dry run: nothing written")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
