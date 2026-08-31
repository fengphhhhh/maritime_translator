#!/usr/bin/env python3
"""Extract and regenerate lib/config/maritime_vocabulary.dart from source documents."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import olefile
import pdfplumber

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "tool" / "sources"
JSON_OUT = ROOT / "tool" / "maritime_vocab_extract.json"
DART_OUT = ROOT / "lib/config/maritime_vocabulary.dart"

DOC_WORDS = SOURCES / "maritime_words.doc"
DOC_VTS = SOURCES / "vts_phrases.doc"
PDF_CORE = SOURCES / "vhf_core100.pdf"


def read_doc_utf16(path: Path) -> str:
    data = olefile.OleFileIO(str(path)).openstream("WordDocument").read()
    return data.decode("utf-16-le", errors="ignore")


def clean_en(text: str) -> str:
    text = text.replace("\r", " ").replace("\n", " ")
    return re.sub(r"\s+", " ", text.strip())


def clean_zh_word(text: str) -> str:
    text = re.sub(r"\s+", "", text.strip())
    for sep in ("，", "/", "（", "("):
        if sep in text:
            text = text.split(sep)[0]
    return text


def clean_zh_phrase(text: str) -> str:
    return re.sub(r"\s+", "", text.replace("\r", "").replace("\n", "")).strip("。")


def parse_word_doc(text: str) -> list[dict[str, str]]:
    chunks = [c.strip() for c in text.split("\x07") if c.strip()]
    entries: list[dict[str, str]] = []
    i = 0
    while i < len(chunks):
        en = chunks[i]
        if re.fullmatch(r"[\d/\s]+", en) or re.search(r"[\u4e00-\u9fff]", en):
            i += 1
            continue
        if (
            i + 1 < len(chunks)
            and re.search(r"[\u4e00-\u9fff]", chunks[i + 1])
            and not re.search(r"[A-Za-z]{4,}", chunks[i + 1])
        ):
            en_clean = clean_en(en)
            zh_clean = clean_zh_word(chunks[i + 1])
            if 2 <= len(en_clean) <= 50 and zh_clean:
                entries.append({"en": en_clean, "zh": zh_clean})
            i += 2
            if i < len(chunks) and re.fullmatch(r"[\d/\s]+", chunks[i]):
                i += 1
        else:
            i += 1

    seen: dict[str, dict[str, str]] = {}
    for entry in entries:
        seen.setdefault(entry["en"].lower(), entry)
    return list(seen.values())


def parse_vts_doc(text: str) -> list[dict[str, str]]:
    chunks = [c.strip() for c in text.split("\x07") if c.strip()]
    pending: dict[str, str] = {}
    phrases: list[dict[str, str]] = []
    sec_re = re.compile(r"^(\d+\.\d+(?:\.\d+)*)\s*(.*)$", re.S)
    category_map = {
        "1": "movement",
        "2": "broadcast",
        "3": "traffic",
        "4": "pilotage",
        "5": "mooring",
        "6": "emergency",
    }

    for chunk in chunks:
        match = sec_re.match(chunk)
        if not match:
            continue
        sec, body = match.group(1), match.group(2).strip()
        has_cn = bool(re.search(r"[\u4e00-\u9fff]", body))
        has_en = bool(re.search(r"[A-Za-z]{3,}", body))
        if has_en and not has_cn:
            pending[sec] = clean_en(body)
        elif has_cn and sec in pending:
            en = pending.pop(sec)
            zh = clean_zh_phrase(body)
            han_count = len(re.findall(r"[\u4e00-\u9fff]", zh))
            if len(en) >= 8 and han_count >= 8:
                phrases.append(
                    {
                        "id": sec,
                        "en": en[:400],
                        "zh": zh[:240],
                        "category": category_map.get(sec.split(".")[0], "general"),
                    }
                )

    seen: set[str] = set()
    unique: list[dict[str, str]] = []
    for phrase in phrases:
        key = phrase["en"][:80].lower()
        if key not in seen:
            seen.add(key)
            unique.append(phrase)
    return unique


def parse_pdf_phrases(path: Path) -> list[dict[str, str]]:
    with pdfplumber.open(str(path)) as pdf:
        text = "\n".join(page.extract_text() or "" for page in pdf.pages)
    text = re.sub(r"船友社文档共享资料库https://capttan.cn", "", text)
    phrases: list[dict[str, str]] = []
    for match in re.finditer(
        r"(\d+)\.\s*英文：(.+?)\s*中文：(.+?)(?=\s*\d+\.\s*英文：|$)", text, re.S
    ):
        phrases.append(
            {
                "id": match.group(1),
                "en": clean_en(match.group(2)),
                "zh": clean_zh_phrase(match.group(3)),
                "category": "vhf_core",
            }
        )
    return phrases


def build_glossary(words: list[dict[str, str]]) -> dict[str, str]:
    priority = {
        "starboard bow": "右舷首",
        "starboard quarter": "右舷尾",
        "starboard side": "右舷",
        "starboard beam": "右舷正横",
        "port bow": "左舷首",
        "port quarter": "左舷尾",
        "port side": "左舷",
        "starboard": "右舷",
        "chief officer": "大副",
        "second mate": "二副",
        "third officer": "三副",
        "bosun": "水手长",
        "underway": "在航",
        "draught": "吃水",
        "draft": "吃水",
        "fairway": "航道",
        "gangway": "舷梯",
        "dredger": "挖泥船",
        "pilot": "引航员",
        "master": "船长",
        "cpa": "最近会遇距离",
        "tcpa": "到达最近会遇点的时间",
        "ukc": "富余水深",
        "vts": "船舶交通管理中心",
        "ecdis": "电子海图显示与信息系统",
        "aio": "海图附加信息",
        "restricted in my ability to maneuver": "操纵能力受限",
        "not under command": "失控",
        "even keel": "平吃水",
        "dead slow": "微速",
        "stand by engine": "主机备车",
        "engine ahead slow": "主机慢速前进",
        "engine astern half": "主机半速后退",
        "stop engine": "主机停车",
        "hard to port": "左满舵",
        "hard to starboard": "右满舵",
        "midships": "回舵至正中",
        "man overboard": "有人落水",
        "abandon ship": "弃船",
        "mayday": "求救",
        "search and rescue": "搜救",
        "oil spill": "溢油",
        "pilot ladder": "引航梯",
        "pilot boat": "引航船",
        "head line": "首缆",
        "spring line": "倒缆",
        "breast line": "横缆",
        "stern spring line": "尾倒缆",
        "mooring operations": "系泊作业",
        "tug assistance": "拖船协助",
        "reporting line": "报告线",
        "anchor position": "锚位",
        "heave up anchor": "起锚",
        "traffic condition": "交通情况",
        "cardinal points": "罗经点",
        "restricted visibility": "能见度受限",
        "gale warning": "大风警告",
        "storm warning": "风暴警告",
        "tropical storm warning": "热带风暴警告",
        "ice warning": "冰情警告",
        "ship to ship transfer": "船对船过驳",
        "free pratique": "入境检疫证",
        "in ballast condition": "压载状态",
        "information received": "信息收到",
        "your information understood": "信息明白",
        "message understood": "信息明白",
        "permission granted": "许可已批准",
        "loud and clear": "声音清晰",
        "over and out": "完毕并结束通讯",
        "alter course": "改向",
        "navigation buoy": "航标",
        "fishing vessel": "渔船",
        "steering gear failure": "操舵装置故障",
        "emergency steering": "应急操舵",
        "fire fighting": "灭火",
        "lifeboat": "救生艇",
        "main engine": "主机",
        "radar is out of order": "雷达故障",
        "gps signal lost": "gps信号丢失",
        "customs inspection": "海关检查",
        "quarantine required": "需检疫",
        "confirm your eta": "确认预计抵达时间",
        "wind direction": "风向",
        "sea state": "海况",
        "present position": "当前船位",
        "proceeding to berth": "正前往泊位",
        "anchor dropped": "已抛锚",
        "shackles": "锚链节",
        "comply with all vts instructions": "遵守交管中心所有指令",
        "autopilot": "自动舵",
        "bilge": "污水沟",
        "thruster": "侧推器",
        "bulbous bow": "球鼻首",
        "bollard": "缆桩",
        "capstan": "绞缆机",
        "windlass": "锚机",
        "forecastle": "首楼",
        "immersion suit": "防水服",
        "breathing apparatus": "呼吸器",
        "extinguisher": "灭火器",
        "compass repeater": "罗经复示器",
        "epirb": "应急无线电示位标",
        "sart": "搜救雷达应答器",
    }

    # Runtime glossary for the 1.5B translator must stay small enough for the
    # 1024-token context after the ChatML system/user turns.
    bridge_terms = re.compile(
        r"anchor|pilot|moor|berth|helm|engine|radar|compass|vts|port|starboard|"
        r"bow|stern|draft|draught|course|speed|wind|fog|visibility|tug|line|"
        r"cargo|fire|life|rescue|mayday|wharf|tide|swell|storm|gale|ice|lock|"
        r"convoy|maneuver|manoeuvre|steer|propeller|thruster|autopilot|bollard|"
        r"capstan|windlass|gangway|fairway|dredge|immigration|customs|quarantine",
        re.I,
    )

    glossary = dict(priority)
    for word in words:
        if len(glossary) >= 110:
            break
        key = word["en"].lower()
        if key in glossary:
            continue
        if len(key.split()) > 3 or len(key) > 35:
            continue
        if bridge_terms.search(key):
            glossary[key] = word["zh"]
    return glossary


def build_hotwords(words: list[dict[str, str]]) -> list[str]:
    seed = [
        "VTS",
        "CPA",
        "TCPA",
        "UKC",
        "ECDIS",
        "AIO",
        "ETA",
        "ETD",
        "SMCP",
        "Mayday",
        "Roger",
        "Over",
        "Out",
        "M/V",
        "Port Bow",
        "Starboard",
        "Starboard Bow",
        "Port Side",
        "Starboard Side",
        "Starboard Beam",
        "Underway",
        "Draught",
        "Draft",
        "Anchor",
        "Anchorage",
        "Pilot",
        "Gangway",
        "Fairway",
        "Master",
        "Chief Officer",
        "Second Mate",
        "Third Officer",
        "Dredger",
        "Head Line",
        "Spring Line",
        "Breast Line",
        "Mooring",
        "Berth",
        "Wharf",
        "Shackles",
        "Restricted Visibility",
        "Man Overboard",
        "Stand By",
        "Engine",
        "Helm",
        "Midships",
        "EPIRB",
        "SART",
        "AIS",
        "GPS",
        "Radar",
        "VHF",
        "Channel",
        "Freeboard",
        "Even Keel",
        "Bollard",
        "Capstan",
        "Windlass",
        "Thruster",
        "Autopilot",
        "Bulbous Bow",
        "Forecastle",
        "Pilot Ladder",
        "Tug Assistance",
        "Oil Spill",
        "Search and Rescue",
        "Alter Course",
        "Dead Slow",
        "Reporting Line",
        "Traffic Condition",
        "Information Received",
        "Loud and Clear",
        "Not Under Command",
        "Heave Up",
        "Permission Granted",
        "Ship to Ship",
        "Ice Warning",
        "Immigration",
        "Customs",
        "Quarantine",
        "Lifeboat",
        "Steering Gear",
        "Main Engine",
        "Immersion Suit",
    ]
    for word in words[:120]:
        term = word["en"]
        if len(term.split()) <= 2:
            seed.append(term)

    seen: set[str] = set()
    hotwords: list[str] = []
    for term in seed:
        key = term.lower()
        if key not in seen:
            seen.add(key)
            hotwords.append(term)
    return hotwords[:90]


def dart_str(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def write_map(name: str, mapping: dict[str, str]) -> str:
    lines = ["  static const Map<String, String> %s = {" % name]
    for key in sorted(mapping.keys(), key=lambda item: (-len(item), item.lower())):
        lines.append(f"    '{dart_str(key)}': '{dart_str(mapping[key])}',")
    lines.append("  };")
    return "\n".join(lines)


def write_list(name: str, items: list[str]) -> str:
    lines = [f"  static const List<String> {name} = ["]
    for item in items:
        lines.append(f"    '{dart_str(item)}',")
    lines.append("  ];")
    return "\n".join(lines)


def write_phrases(name: str, doc: str, items: list[dict[str, str]]) -> str:
    lines = [f"  /// {doc}", f"  static const List<MaritimePhrase> {name} = ["]
    for item in items:
        lines.append(
            "    MaritimePhrase(id: '%s', category: '%s', en: '%s', zh: '%s'),"
            % (
                dart_str(item["id"]),
                dart_str(item["category"]),
                dart_str(item["en"]),
                dart_str(item["zh"]),
            )
        )
    lines.append("  ];")
    return "\n".join(lines)


def generate_dart(
    hotwords: list[str],
    glossary: dict[str, str],
    pdf_phrases: list[dict[str, str]],
    vts_phrases: list[dict[str, str]],
    words: list[dict[str, str]],
) -> str:
    word_glossary = {word["en"].lower(): word["zh"] for word in words}
    parts = [
        "/// Organized maritime vocabulary extracted from training documents.",
        "///",
        "/// Sources:",
        "/// - 三副岗位 VHF 核心 100 句 (PDF)",
        "/// - 航海英语听力与会话单词 (DOC)",
        "/// - VTS 水域常用通信用语汇编 (DOC)",
        "///",
        "/// Regenerate: `python3 tool/extract_maritime_vocab.py`",
        "library;",
        "",
        "/// A bilingual SMCP phrase pair.",
        "class MaritimePhrase {",
        "  const MaritimePhrase({",
        "    required this.id,",
        "    required this.category,",
        "    required this.en,",
        "    required this.zh,",
        "  });",
        "",
        "  final String id;",
        "  final String category;",
        "  final String en;",
        "  final String zh;",
        "}",
        "",
        "abstract final class MaritimeVocabulary {",
        write_list("hotwords", hotwords),
        "",
        write_map("glossary", glossary),
        "",
        write_phrases("vhfCorePhrases", "三副岗位 VHF 核心口语 100 句", pdf_phrases),
        "",
        write_phrases("vtsPhrases", "交通运输部 VTS 水域常用通信用语", vts_phrases),
        "",
        write_map("wordGlossary", word_glossary),
        "}",
        "",
    ]
    return "\n".join(parts)


def main() -> int:
    for path in (DOC_WORDS, DOC_VTS, PDF_CORE):
        if not path.exists():
            print(f"Missing source document: {path}", file=sys.stderr)
            return 1

    words = parse_word_doc(read_doc_utf16(DOC_WORDS))
    vts_phrases = parse_vts_doc(read_doc_utf16(DOC_VTS))
    pdf_phrases = parse_pdf_phrases(PDF_CORE)
    glossary = build_glossary(words)
    hotwords = build_hotwords(words)

    payload = {
        "stats": {
            "pdf_phrases": len(pdf_phrases),
            "word_entries": len(words),
            "vts_phrases": len(vts_phrases),
            "glossary": len(glossary),
            "hotwords": len(hotwords),
        },
        "pdf_phrases": pdf_phrases,
        "word_entries": words,
        "vts_phrases": vts_phrases,
        "glossary": glossary,
        "hotwords": hotwords,
    }
    JSON_OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    DART_OUT.write_text(
        generate_dart(hotwords, glossary, pdf_phrases, vts_phrases, words),
        encoding="utf-8",
    )

    print(json.dumps(payload["stats"], indent=2))
    print(f"Wrote {DART_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
