"""Tests for scripts/migrate-notes.py.

Run from the repo root:  python3 -B -m unittest tests/test_migrate.py
(-B: no __pycache__ in the repo)
The fixtures under tests/fixtures/migrate/ are invented notes that copy the
structure of the old outline files (tabs, 4 spaces, 2-space slips, markers,
key: lines, separators, wrapped lines, URLs, unicode, no final newline).
expected/ holds the reviewed output for them (--date 2026-01-01).
"""

import contextlib
import hashlib
import importlib.util
import io
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True  # importing the script leaves no __pycache__

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "migrate-notes.py"
FIXTURES = REPO / "tests" / "fixtures" / "migrate"
EXPECTED = FIXTURES / "expected"
SOURCES = [
    FIXTURES / "Documents" / "notes.yaml",
    FIXTURES / "Desktop" / "notes.yaml",
    *sorted((FIXTURES / "sublime-docs").glob("*.yaml")),
]
DATE = "2026-01-01"
# The agent contract for open tasks (docs/NOTES-CONVENTION.md).
AGENT_OPEN = re.compile(r"^\s*- \[[ !]\]", re.MULTILINE)

_spec = importlib.util.spec_from_file_location("migrate_notes", SCRIPT)
mig = importlib.util.module_from_spec(_spec)
sys.modules["migrate_notes"] = mig
_spec.loader.exec_module(mig)


def convert(text, **kw):
    return mig.migrate_text(text, title="t", project="t", date=DATE, **kw)


def body(text, **kw):
    """Markdown lines after the front matter."""
    return convert(text, **kw).markdown.split("---\n", 2)[2].strip("\n").split("\n")


def run_cli(*args):
    cmd = [sys.executable, "-B", str(SCRIPT), *map(str, args)]
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class TempDirCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="migrate-test-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp)

    def make_source(self, rel, text="- a task\n"):
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path


class Rules(unittest.TestCase):
    def test_markers(self):
        self.assertEqual(body("-* a\n+ b\n- c\n"), ["- [!] a", "- [x] b", "- [ ] c"])

    def test_dash_as_note_keeps_plain_dash(self):
        self.assertEqual(
            body("- c\n-* a\n+ b\n", dash_as_note=True), ["- c", "- [!] a", "- [x] b"]
        )

    def test_marker_needs_a_space_except_dash_before_a_letter(self):
        res = convert("+41 79\n--x\n-1 degree\n->arrow\n-word\n")
        self.assertEqual(
            res.markdown.split("---\n", 2)[2].strip().split("\n"),
            ["+41 79", "--x", "-1 degree", "->arrow", "- [ ] word"],
        )
        self.assertIn((5, 'no space after "-", read as a task'), res.review)

    def test_tabs_and_spaces_give_the_same_levels(self):
        tabs = "a:\n\t- one\n\t\t- two\n\t\t\t- three\n\t- four\n"
        spaces = tabs.replace("\t", "    ")
        mixed = "a:\n  \t- one\n\t  \t- two\n\t\t\t- three\n\t- four\n"
        want = ["## a", "", "- [ ] one", "  - [ ] two", "    - [ ] three", "- [ ] four"]
        self.assertEqual(body(tabs), want)
        self.assertEqual(body(spaces), want)
        self.assertEqual(body(mixed), want)
        self.assertEqual(convert(tabs).indent, "tabs")
        self.assertEqual(convert(spaces).indent, "spaces")
        self.assertEqual(convert(mixed).indent, "tabs+spaces")

    def test_level_jump_becomes_one_level(self):
        self.assertEqual(
            body("- a\n\t\t\t- b\n\t- c\n"), ["- [ ] a", "  - [ ] b", "  - [ ] c"]
        )

    def test_key_lines(self):
        self.assertEqual(
            body("top: \n\tsub:\n\t\t- x\n"), ["## top", "", "- **sub**", "  - [ ] x"]
        )

    def test_long_colon_line_is_text(self):
        line = "x" * (mig.KEY_MAX + 1) + ":"
        self.assertEqual(body(line + "\n\t- a\n"), [line, "- [ ] a"])

    def test_setext_trap(self):
        self.assertEqual(body("para\n-----\nmore\n"), ["para", "", "---", "", "more"])
        self.assertEqual(body("- a\n--\n- b\n"), ["- [ ] a", "", "---", "", "- [ ] b"])
        # No dash or equals line may directly follow text in any fixture output.
        for path in EXPECTED.glob("*.md"):
            lines = path.read_text(encoding="utf-8").split("---\n", 2)[2].split("\n")
            for prev, line in itertools.pairwise(lines):
                if re.fullmatch(r"\s*(-+|=+)\s*", line):
                    self.assertEqual(prev, "", f"{path.name}: setext underline")

    def test_continuation_join(self):
        for lead in (" ", "  ", "   "):
            self.assertEqual(
                body(f"- item\n{lead}wrapped part\n"), ["- [ ] item wrapped part"]
            )
        self.assertEqual(body("text\n next\n"), ["text next"])
        self.assertEqual(convert("- item\n  wrapped\n").stats["joined"], 1)

    def test_no_join_without_a_line_to_join(self):
        self.assertEqual(body("- item\n\n  alone\n"), ["- [ ] item", "", "  alone"])
        self.assertEqual(body("key:\n  text\n"), ["## key", "", "text"])
        self.assertEqual(body("- item\n\tchild\n"), ["- [ ] item", "  child"])
        self.assertEqual(body("- item\n    child\n"), ["- [ ] item", "  child"])

    def test_text_after_an_item_is_not_glued_to_it(self):
        self.assertEqual(body("- a\nnote\n"), ["- [ ] a", "", "note"])
        self.assertEqual(
            body("- a\n\t- b\n\tnote\n"), ["- [ ] a", "  - [ ] b", "", "  note"]
        )

    def test_empty_items_are_dropped(self):
        res = convert("- a\n- \n-*\n+\n")
        self.assertEqual(res.markdown.split("---\n", 2)[2].strip(), "- [ ] a")
        self.assertEqual(res.stats["dropped"], 3)

    def test_blank_runs_collapse(self):
        self.assertEqual(
            body("\n\n- a\n\n\n \n\t\n- b\n\n"), ["- [ ] a", "", "- [ ] b"]
        )

    def test_front_matter(self):
        md = mig.migrate_text("- a\n", "My notes", "my-notes", DATE).markdown
        self.assertTrue(
            md.startswith(
                "---\ntitle: My notes\nproject: my-notes\ntags: [migrated]\n"
                "date: 2026-01-01\n---\n\n- [ ] a\n"
            ),
            md,
        )
        self.assertEqual(mig.yaml_str("a: b"), '"a: b"')
        self.assertEqual(mig.yaml_str("yes"), '"yes"')
        self.assertEqual(mig.yaml_str("2024"), '"2024"')

    def test_crlf_bom_and_trailing_spaces(self):
        self.assertEqual(body("\ufeff- a  \r\n\t- b\t\r\n"), ["- [ ] a", "  - [ ] b"])

    def test_unicode_and_inner_tabs_are_kept(self):
        self.assertEqual(body("- Zoë ⚡ 🦀\tmore\n"), ["- [ ] Zoë ⚡ 🦀\tmore"])

    def test_slugs(self):
        self.assertEqual(mig.slugify("My reading list"), "my-reading-list")
        self.assertEqual(mig.slugify("Windows 101"), "windows-101")
        self.assertEqual(mig.slugify("Über_Notes"), "über-notes")
        self.assertEqual(mig.slugify("***"), "notes")

    def test_name_collisions(self):
        paths = [
            Path("/x/Documents/notes.yaml"),
            Path("/x/Desktop/notes.yaml"),
            Path("/x/sublime-docs/reading list.yaml"),
        ]
        want = ["notes-documents.md", "notes-desktop.md", "reading-list.md"]
        self.assertEqual(mig.output_names(paths), want)
        self.assertEqual(mig.output_names(paths[::-1]), want[::-1])
        same_parent = [Path("/b/x/notes.yaml"), Path("/a/x/notes.yaml")]
        self.assertEqual(mig.output_names(same_parent), ["notes-x-2.md", "notes-x.md"])


class SafetyNet(unittest.TestCase):
    def test_count_check_catches_a_wrong_marker(self):
        wrong = mock.patch.dict(mig.TASK, {"+": "- [ ] "})
        expect = self.assertRaisesRegex(
            mig.MigrationError, r"\+ -> \[x\]: 1 expected, 0"
        )
        with wrong, expect:
            convert("+ done\n- open\n")

    def test_count_check_catches_a_dropped_item(self):
        real = mig.convert

        def drops_last_line(lines, dash_as_note=False):
            out, stats, review = real(lines, dash_as_note)
            return out[:-1], stats, review

        with mock.patch.object(mig, "convert", drops_last_line):
            with self.assertRaisesRegex(
                mig.MigrationError, r"- -> \[ \]: 2 expected, 1"
            ):
                convert("- a\n- b\n")
            # Same marker counts, but a text line vanished: the text check fires.
            with self.assertRaisesRegex(mig.MigrationError, r"line 2: text missing"):
                convert("- a\nplain\n")

    def test_cli_does_not_write_a_file_that_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "src"
            src.mkdir()
            (src / "good.yaml").write_text("- a\n", encoding="utf-8")
            (src / "bad.yaml").write_text("+ b\n", encoding="utf-8")
            out = Path(tmp) / "out"
            err = io.StringIO()
            with (
                mock.patch.dict(mig.TASK, {"+": "- [ ] "}),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(err),
            ):
                code = mig.main(
                    ["--out", str(out), str(src / "good.yaml"), str(src / "bad.yaml")]
                )
            self.assertEqual(code, 1)
            self.assertIn("file not written", err.getvalue())
            self.assertTrue((out / "good.md").exists())
            self.assertFalse((out / "bad.md").exists())


class Cli(TempDirCase):
    def test_dry_run_writes_nothing(self):
        src = self.make_source("old/notes.yaml", "topic:\n\t- a\n")
        out = self.tmp / "out"
        res = run_cli("--dry-run", "--project", "Home Lab", "--out", out, src)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertFalse(out.exists())
        self.assertIn(
            "markers  -* 0 -> [!] 0 | + 0 -> [x] 0 | - 1 -> [ ] 1", res.stdout
        )
        self.assertIn("+project: home-lab", res.stdout)
        self.assertIn("+- [ ] a", res.stdout)
        self.assertIn("dry run: nothing written", res.stdout)

    def test_refuses_to_write_inside_a_source_directory(self):
        src = self.make_source("old/notes.yaml")
        for out in (src.parent, src.parent / "md"):
            res = run_cli("--out", out, src)
            self.assertEqual(res.returncode, 2)
            self.assertIn("inside the source folder", res.stderr)
        self.assertEqual(sorted(p.name for p in src.parent.iterdir()), ["notes.yaml"])

    def test_refuses_to_overwrite(self):
        first = self.make_source("a/first.yaml")
        second = self.make_source("b/second.yaml")
        out = self.tmp / "out"
        out.mkdir()
        (out / "second.md").write_text("keep me\n", encoding="utf-8")
        res = run_cli("--out", out, first, second)
        self.assertEqual(res.returncode, 2)
        self.assertIn("refusing to overwrite", res.stderr)
        self.assertEqual((out / "second.md").read_text(encoding="utf-8"), "keep me\n")
        self.assertFalse((out / "first.md").exists())

    def test_fixtures_match_the_reviewed_output(self):
        before = {p: sha(p) for p in SOURCES}
        out = self.tmp / "out"
        res = run_cli("--date", DATE, "--out", out, *SOURCES)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual({p: sha(p) for p in SOURCES}, before, "sources changed")
        written = sorted(p.name for p in out.iterdir())
        self.assertEqual(written, sorted(p.name for p in EXPECTED.glob("*.md")))
        for name in written:
            with self.subTest(name=name):
                self.assertEqual(
                    (out / name).read_text(encoding="utf-8"),
                    (EXPECTED / name).read_text(encoding="utf-8"),
                )

    def test_agent_regex_finds_every_open_task(self):
        names = mig.output_names([p.resolve() for p in SOURCES])
        for src, name in zip(SOURCES, names):
            with self.subTest(name=name):
                old = src.read_text(encoding="utf-8").splitlines()
                # Counted here with separate regexes, not with the script's.
                items = [x.strip() for x in old if not re.fullmatch(r"\s*-{2,}\s*", x)]
                n_open = sum(
                    bool(re.match(r"-\*\s*\S|-(\s+\S|[^\W\d_])", x)) for x in items
                )
                n_done = sum(bool(re.match(r"\+\s+\S", x)) for x in items)
                md = (EXPECTED / name).read_text(encoding="utf-8")
                self.assertEqual(len(AGENT_OPEN.findall(md)), n_open)
                self.assertEqual(len(re.findall(r"(?m)^\s*- \[x\] ", md)), n_done)


LUA_PARSE = r"""
local src = table.concat(vim.fn.readfile(vim.env.MIGRATE_MD), '\n') .. '\n'
local root = vim.treesitter.get_string_parser(src, 'markdown'):parse()[1]:root()
local res = { counts = {}, items = {} }
local function walk(node)
  local t = node:type()
  res.counts[t] = (res.counts[t] or 0) + 1
  if t == 'list_item' then
    local kind = 'plain'
    for child in node:iter_children() do
      local ct = child:type()
      if ct == 'task_list_marker_unchecked' then
        kind = 'open'
      elseif ct == 'task_list_marker_checked' then
        kind = 'done'
      elseif ct == 'paragraph' and kind == 'plain' then
        if vim.treesitter.get_node_text(child, src):sub(1, 4) == '[!] ' then kind = 'important' end
      end
    end
    res.items[tostring(node:range())] = kind
  end
  for child in node:iter_children() do
    walk(child)
  end
end
walk(root)
vim.fn.writefile({ vim.json.encode(res) }, vim.env.MIGRATE_JSON)
"""


@unittest.skipUnless(shutil.which("nvim"), "nvim not on PATH")
class MarkdownParse(TempDirCase):
    """Neovim's own Markdown parser must see every task as a task."""

    def parse(self, md_path):
        lua, out = self.tmp / "parse.lua", self.tmp / "parse.json"
        lua.write_text(LUA_PARSE, encoding="utf-8")
        env = dict(os.environ, MIGRATE_MD=str(md_path), MIGRATE_JSON=str(out))
        # Any file nvim might create lands in the temp dir.
        for var in ("CONFIG", "DATA", "STATE", "CACHE"):
            env[f"XDG_{var}_HOME"] = str(self.tmp / var.lower())
        cmd = ["nvim", "--clean", "--headless", "-i", "NONE"]
        cmd += ["-c", f"luafile {lua}", "-c", "qa!"]
        subprocess.run(cmd, env=env, capture_output=True, timeout=60, check=True)
        res = json.loads(out.read_text(encoding="utf-8"))
        return res["counts"], res["items"] or {}  # an empty Lua table encodes as []

    def test_expected_outputs_parse_as_intended(self):
        kinds = {"[ ]": "open", "[x]": "done", "[!]": "important"}
        for path in sorted(EXPECTED.glob("*.md")):
            with self.subTest(name=path.name):
                counts, items = self.parse(path)
                lines = path.read_text(encoding="utf-8").split("\n")
                body_start = lines.index("---", 1) + 1
                for key in ("setext_heading", "indented_code_block", "html_block"):
                    self.assertNotIn(key, counts)
                self.assertEqual(counts.get("minus_metadata"), 1)
                self.assertEqual(
                    counts.get("thematic_break", 0), lines[body_start:].count("---")
                )
                headings = [x for x in lines if x.startswith("## ")]
                self.assertEqual(counts.get("atx_heading", 0), len(headings))
                for row, line in enumerate(lines):
                    m = re.match(r"\s*- (\[[ x!]\])( |$)", line)
                    if m:
                        self.assertEqual(items.get(str(row)), kinds[m.group(1)], line)


if __name__ == "__main__":
    unittest.main()
