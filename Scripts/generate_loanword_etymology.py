#!/usr/bin/env python3
"""Generate Kotoba's built-in loanword sidecar from attributable data.

Primary data is egg rolls' tagged VocabFurigana field. For katakana-tagged
records this field carries the source form (and an optional language prefix).
JMdict is a conservative fallback and supplies its explicit lsource flags.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import re
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path
import xml.etree.ElementTree as ET


XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
LEVELS = ("N5", "N4", "N3", "N2", "N1")
PRIORITY_PREFIXES = ("ichi", "news", "spec", "gai", "nf")
EGG_ROLLS_SOURCE = "https://github.com/5mdld/anki-jlpt-decks/blob/d40f6db3aa24f803216b654f7f7b76a4222da3a2/deck-source/notes.csv"
JMDICT_SOURCE = "https://www.edrdg.org/pub/Nihongo/JMdict_e.gz"
LANGUAGE_MARKERS = {
    "和": ("eng", True),
    "英": ("eng", False),
    "ド": ("ger", False), "独": ("ger", False),
    "フ": ("fre", False), "仏": ("fre", False), "法": ("fre", False),
    "オ": ("dut", False), "蘭": ("dut", False),
    "ポ": ("por", False), "葡": ("por", False),
    "イ": ("ita", False), "伊": ("ita", False),
    "ラ": ("lat", False), "羅": ("lat", False),
    "ロ": ("rus", False), "露": ("rus", False),
}
MARKER_PATTERN = re.compile(r"^[（(]([^）)]+)[）)]\s*")


@dataclass(frozen=True, order=True)
class Source:
    term: str
    language: str
    wasei: bool = False
    partial: bool = False


@dataclass
class JMdictEntry:
    sequence: str
    sources: set[Source]
    has_lsource: bool
    prioritized: bool


def nfkc(value: str) -> str:
    return unicodedata.normalize("NFKC", value.strip())


def hiragana(value: str) -> str:
    result = []
    for character in nfkc(value):
        code = ord(character)
        result.append(chr(code - 0x60) if 0x30A1 <= code <= 0x30F6 else character)
    return "".join(result)


def identity(expression: str, reading: str) -> tuple[str, str]:
    return nfkc(expression), hiragana(reading)


def source_has_latin(value: str) -> bool:
    return any("LATIN" in unicodedata.name(character, "") for character in nfkc(value))


def has_katakana(value: str) -> bool:
    return any(
        "ァ" <= character <= "ヿ"
        or "ㇰ" <= character <= "ㇿ"
        or "ｦ" <= character <= "ﾟ"
        for character in value
    )


def read_words(resources: Path) -> list[dict[str, object]]:
    words: list[dict[str, object]] = []
    for level in LEVELS:
        path = resources / f"eggrolls_kotoba_{level}_strict.csv"
        with path.open(encoding="utf-8", newline="") as handle:
            for order, row in enumerate(csv.DictReader(handle)):
                words.append({
                    **row,
                    "wordBook": level,
                    "order": order,
                    "identity": identity(row["expression"], row["reading"]),
                    "isTagged": "カタカナ語" in set(filter(None, row["tags"].split(";"))),
                })
    return words


def read_egg_rolls(path: Path) -> dict[tuple[str, str], list[str]]:
    sources: dict[tuple[str, str], list[str]] = defaultdict(list)
    with path.open(encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if not row or row[0].startswith("#") or len(row) < 39:
                continue
            if "::カタカナ語" not in row[38]:
                continue
            level_match = re.search(r"::[1-5]-N([1-5])", row[1])
            if level_match is None:
                continue
            level = f"N{level_match.group(1)}"
            sources[(level, nfkc(row[3]))].append(row[6].strip())
    return sources


def parse_egg_rolls_source(raw_value: str) -> Source | None:
    # The first usable segment is the primary form. Two records currently add
    # a French alternative after an English primary, which the one-language
    # app model intentionally does not flatten into a misleading language.
    for raw_segment in re.split(r"[；;]", raw_value):
        segment = nfkc(raw_segment)
        marker_match = MARKER_PATTERN.match(segment)
        marker = marker_match.group(1) if marker_match else None
        term = segment[marker_match.end():].strip() if marker_match else segment
        if not term or not source_has_latin(term):
            continue
        language, wasei = LANGUAGE_MARKERS.get(marker, ("eng", False))
        if marker is not None and marker not in LANGUAGE_MARKERS:
            continue
        return Source(term=term, language=language, wasei=wasei)
    return None


def egg_rolls_source_for_word(
    word: dict[str, object],
    raw_sources: dict[tuple[str, str], list[str]],
    strict_expression_counts: Counter[tuple[str, str]],
) -> Source | None:
    if not word["isTagged"]:
        return None
    key = (str(word["wordBook"]), nfkc(str(word["expression"])))
    if strict_expression_counts[key] != 1:
        return None
    candidates = [source for raw in raw_sources.get(key, []) if (source := parse_egg_rolls_source(raw))]
    if not candidates:
        return None
    attributes = {(source.language, source.wasei, source.partial) for source in candidates}
    if len(attributes) != 1:
        return None
    terms = list(dict.fromkeys(source.term for source in candidates))
    language, wasei, partial = next(iter(attributes))
    return Source(" / ".join(terms), language, wasei, partial)


def open_jmdict(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rb")
    return path.open("rb")


def parse_jmdict(
    path: Path,
    wanted: set[tuple[str, str]],
) -> dict[tuple[str, str], list[JMdictEntry]]:
    matches: dict[tuple[str, str], list[JMdictEntry]] = defaultdict(list)
    with open_jmdict(path) as handle:
        for _, entry in ET.iterparse(handle, events=("end",)):
            if entry.tag != "entry":
                continue
            kebs = [node.text or "" for node in entry.findall("k_ele/keb")]
            prioritized = any(
                (node.text or "").startswith(PRIORITY_PREFIXES)
                for node in entry.findall("k_ele/ke_pri") + entry.findall("r_ele/re_pri")
            )
            emitted: set[tuple[str, str]] = set()
            for reading_node in entry.findall("r_ele"):
                reading = reading_node.findtext("reb", "")
                restrictions = [node.text or "" for node in reading_node.findall("re_restr")]
                expressions = list(restrictions or kebs or [reading])
                # Built-in kana spellings must see both kana-only entries and
                # usually-kana JMdict entries that also happen to have kanji.
                if identity(reading, reading) in wanted:
                    expressions.append(reading)
                for expression in expressions:
                    key = identity(expression, reading)
                    if key not in wanted or key in emitted:
                        continue
                    emitted.add(key)
                    sources: set[Source] = set()
                    has_lsource = False
                    for sense in entry.findall("sense"):
                        stagk = {nfkc(node.text or "") for node in sense.findall("stagk")}
                        stagr = {hiragana(node.text or "") for node in sense.findall("stagr")}
                        if stagk and nfkc(expression) not in stagk:
                            continue
                        if stagr and hiragana(reading) not in stagr:
                            continue
                        for node in sense.findall("lsource"):
                            has_lsource = True
                            sources.add(Source(
                                term=nfkc(node.text or ""),
                                language=(node.attrib.get(XML_LANG, "eng").strip() or "eng").lower(),
                                wasei=node.attrib.get("ls_wasei") == "y",
                                partial=node.attrib.get("ls_type") == "part",
                            ))
                    matches[key].append(JMdictEntry(
                        sequence=entry.findtext("ent_seq", ""),
                        sources=sources,
                        has_lsource=has_lsource,
                        prioritized=prioritized,
                    ))
            entry.clear()
    return matches


def select_jmdict_source(entries: list[JMdictEntry]) -> Source | None:
    def usable(entry: JMdictEntry) -> Source | None:
        if not entry.has_lsource or len(entry.sources) != 1:
            return None
        source = next(iter(entry.sources))
        return source if source.term else None

    if len(entries) == 1:
        return usable(entries[0])
    prioritized = [entry for entry in entries if entry.prioritized]
    if len(prioritized) == 1:
        return usable(prioritized[0])
    return None


def build_rows(
    words: list[dict[str, object]],
    egg_rolls: dict[tuple[str, str], list[str]],
    jmdict: dict[tuple[str, str], list[JMdictEntry]],
) -> tuple[list[list[str]], list[dict[str, object]]]:
    expression_counts = Counter(
        (str(word["wordBook"]), nfkc(str(word["expression"]))) for word in words
    )
    sidecar_rows: list[list[str]] = []
    audit_rows: list[dict[str, object]] = []

    for word in words:
        primary = egg_rolls_source_for_word(word, egg_rolls, expression_counts)
        fallback = select_jmdict_source(jmdict.get(word["identity"], []))
        source = primary or fallback
        provenance = "eggRolls" if primary else ("jmdict" if fallback else "")
        if primary and fallback:
            source = Source(
                term=primary.term,
                language=primary.language,
                wasei=primary.wasei or fallback.wasei,
                partial=primary.partial or fallback.partial,
            )
            provenance = "eggRolls+jmdictFlags"

        identified = bool(word["isTagged"]) or fallback is not None
        audit_rows.append({
            "wordBook": word["wordBook"],
            "expression": word["expression"],
            "reading": word["reading"],
            "katakana": has_katakana(str(word["expression"])),
            "tagged": word["isTagged"],
            "identified": identified,
            "source": source,
            "provenance": provenance,
        })
        if source is None:
            continue
        sidecar_rows.append([
            str(word["wordBook"]), str(word["expression"]), str(word["reading"]),
            source.term, source.language,
            str(source.wasei).lower(), str(source.partial).lower(),
        ])
    return sidecar_rows, audit_rows


def write_outputs(
    sidecar_rows: list[list[str]],
    audit_rows: list[dict[str, object]],
    output: Path,
) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with (output / "builtin_loanword_etymology.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["wordBook", "expression", "reading", "sourceTerm", "sourceLanguage", "isWasei", "isPartial"])
        writer.writerows(sidecar_rows)

    with (output / "Kotoba_Loanword_Etymology_Corrections.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["wordBook", "expression", "reading", "tagged", "sourceTerm", "sourceLanguage", "isWasei", "isPartial", "provenance", "status"])
        for row in audit_rows:
            if not row["identified"]:
                continue
            source = row["source"]
            writer.writerow([
                row["wordBook"], row["expression"], row["reading"],
                str(row["tagged"]).lower(), source.term if source else "",
                source.language if source else "", str(source.wasei).lower() if source else "",
                str(source.partial).lower() if source else "", row["provenance"],
                "covered" if source else "missingReliableSource",
            ])

    per_level: dict[str, Counter[str]] = {level: Counter() for level in LEVELS}
    for row in audit_rows:
        stats = per_level[str(row["wordBook"])]
        source = row["source"]
        stats["total"] += 1
        stats["katakana"] += int(bool(row["katakana"]))
        stats["tagged"] += int(bool(row["tagged"]))
        stats["identified"] += int(bool(row["identified"]))
        stats["covered"] += int(source is not None)
        stats["language"] += int(source is not None and bool(source.language))
        stats["wasei"] += int(source is not None and source.wasei)
        stats["partial"] += int(source is not None and source.partial)
        stats["missing"] += int(bool(row["identified"]) and source is None)

    totals: Counter[str] = Counter()
    for stats in per_level.values():
        totals.update(stats)
    lines = [
        "# Kotoba Loanword Etymology Generation Audit", "",
        f"- Generated: {date.today().isoformat()}",
        f"- Primary source: {EGG_ROLLS_SOURCE}",
        f"- Supplemental source: {JMDICT_SOURCE}",
        "- App identity: wordBook + NFKC expression + NFKC/hiragana reading.",
        "- No per-word overrides are used.", "",
        "| 词书 | 总词数 | 含片假名 | 上游标记 | 可确认候选 | 有可靠词源 | 有语言 | 和制 | Partial | 缺少可靠词源 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for level in LEVELS:
        s = per_level[level]
        lines.append(f"| {level} | {s['total']} | {s['katakana']} | {s['tagged']} | {s['identified']} | {s['covered']} | {s['language']} | {s['wasei']} | {s['partial']} | {s['missing']} |")
    lines.extend([
        f"| **总计** | **{totals['total']}** | **{totals['katakana']}** | **{totals['tagged']}** | **{totals['identified']}** | **{totals['covered']}** | **{totals['language']}** | **{totals['wasei']}** | **{totals['partial']}** | **{totals['missing']}** |",
        "",
        "egg rolls data is used under CC BY-NC 4.0. JMdict-derived data is used under CC BY-SA 4.0.",
    ])
    (output / "Kotoba_Loanword_Etymology_Audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--egg-rolls-notes", type=Path, required=True)
    parser.add_argument("--jmdict", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    words = read_words(args.resources)
    jmdict = parse_jmdict(args.jmdict, {word["identity"] for word in words})
    sidecar_rows, audit_rows = build_rows(words, read_egg_rolls(args.egg_rolls_notes), jmdict)
    write_outputs(sidecar_rows, audit_rows, args.output)


if __name__ == "__main__":
    main()
