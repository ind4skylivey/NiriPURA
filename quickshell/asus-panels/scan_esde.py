#!/usr/bin/env python3
"""Read-only ES-DE library scanner. Writes ~/.cache/asus-panels/index.json and prints it."""
from __future__ import annotations

import json
import os
import re
import sys
import time
import fnmatch
from pathlib import Path
from xml.etree import ElementTree as ET

HOME = Path.home()
ESDE = HOME / "ES-DE"
CACHE_DIR = HOME / ".cache" / "asus-panels"
CACHE_FILE = CACHE_DIR / "index.json"
STOCK_SYSTEMS = Path("/usr/share/es-de/resources/systems/linux/es_systems.xml")
STOCK_RULES = Path("/usr/share/es-de/resources/systems/linux/es_find_rules.xml")
CUSTOM_DIR = ESDE / "custom_systems"

# Personal media mount and ES-DE library. Override if the drive is mounted elsewhere.
HD2 = Path(os.environ.get("NIRIPURA_HD2", "/media/il1v3y/HD2"))
ESDE_MEDIA = Path(os.environ.get("ESDE_MEDIA_ROOT", str(HD2 / "Gameru" / "EmulationStation DE")))
DEFAULT_ROM_ROOT = Path(os.environ.get("ESDE_ROM_ROOT", str(ESDE_MEDIA / "ROMs")))
DEFAULT_GAMELIST_ROOT = Path(os.environ.get("ESDE_GAMELIST_ROOT", str(ESDE_MEDIA / "gamelists")))
DEFAULT_DOWNLOADED_MEDIA = Path(os.environ.get("ESDE_DOWNLOADED_MEDIA", str(ESDE_MEDIA / "downloaded_media")))

MEDIA_SUBDIRS = {
    "covers", "screenshots", "titlescreens", "physicalmedia", "3dboxes",
    "backcovers", "videos", "manuals", "marquees", "miximages", "fanart",
    "media", "images", "downloaded_media", "boxart", "thumbnails",
}
SKIP_FILES = {"systeminfo.txt", "gamelist.xml", ".ds_store", "desktop.ini"}

# Extra resolver paths that ES-DE find-rules miss on this machine (read-only).
EXTRA_EMU_PATHS = {
    "EDEN": [
        HOME / ".local/bin/eden",
        HD2 / "Apps" / "Eden",
    ],
    "RYUJINX": [
        HD2 / "Gameru" / "Emulation" / "ryujinx" / "publish" / "Ryujinx",
        HD2 / "Gameru" / "Emulation" / "ryujinx" / "publish" / "Ryujinx.sh",
    ],
    "LICHII": [
        HD2 / "Apps" / "Lichii" / "lichii.AppImage",
    ],
    "CHEEZYEMU": [
        HD2 / "Apps" / "CheezyEmu" / "cheezyemu-linux-x86_64-pgo.AppImage",
    ],
    "DUSK": [
        HOME / ".local/bin/dusk",
    ],
    "PCSX2": [
        HOME / ".local/bin/pcsx2",
        HOME / ".local/bin/pcsx2-wrapper.sh",
    ],
    "DUCKSTATION": [
        HOME / ".local/bin/duckstation",
        HOME / ".local/bin/duckstation-wrapper.sh",
    ],
    "DOLPHIN": [
        Path("/usr/bin/dolphin-emu"),
        HOME / ".local/bin/dolphin",
    ],
    "RPCS3": [
        HOME / ".local/bin/rpcs3",
        HD2 / "Gameru" / "Emulation" / "ps3" / "rpcs3" / "rpcs3.sh",
    ],
    "AZAHAR": [
        HOME / ".local/bin/azahar",
    ],
    "REDREAM": [
        HOME / ".local/bin/redream",
        HD2 / "Apps" / "redream",
        HD2 / "Gameru" / "Emulation" / "dreamcast" / "redream" / "redream",
    ],
}


def parse_settings(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text(errors="replace").splitlines():
        m = re.search(r'<(string|bool|int|float)\s+name="([^"]+)"\s+value="([^"]*)"', line)
        if m:
            out[m.group(2)] = m.group(3)
    return out


def expand_user(p: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(p)))


def parse_find_rules(path: Path) -> dict[str, list[tuple[str, list[str]]]]:
    """name -> list of (rule_type, entries)."""
    rules: dict[str, list[tuple[str, list[str]]]] = {}
    if not path.exists():
        return rules
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return rules
    for el in root:
        name = (el.get("name") or "").strip()
        if not name:
            continue
        items: list[tuple[str, list[str]]] = []
        for rule in el:
            typ = rule.get("type") or ""
            entries = [(e.text or "").strip() for e in rule if (e.text or "").strip()]
            items.append((typ, entries))
        rules[f"{el.tag}:{name}"] = items
        # Prefer emulator rules under the bare name; cores stay under core:NAME.
        if el.tag == "emulator" or name not in rules:
            rules[name] = items
    return rules


def first_existing(patterns: list[str], is_dir: bool = False) -> Path | None:
    for raw in patterns:
        pat = str(expand_user(raw))
        if any(ch in pat for ch in "*?["):
            parent = Path(pat).parent
            name = Path(pat).name
            try:
                if parent.exists():
                    for cand in sorted(parent.glob(name)):
                        if cand.exists() and (cand.is_dir() if is_dir else cand.is_file()):
                            return cand
            except OSError:
                continue
            continue
        p = Path(pat)
        if p.exists() and (p.is_dir() if is_dir else (p.is_file() or os.access(p, os.X_OK) or p.is_symlink())):
            return p
    return None


def which(name: str) -> Path | None:
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return p
    # always check ~/.local/bin even if PATH is slim
    p = HOME / ".local/bin" / name
    if p.is_file() and os.access(p, os.X_OK):
        return p
    p = Path("/usr/bin") / name
    if p.is_file() and os.access(p, os.X_OK):
        return p
    return None


def resolve_named(name: str, rules: dict) -> Path | None:
    key = name.upper()
    items = rules.get(key) or rules.get(f"emulator:{key}") or rules.get(f"core:{key}") or []
    for typ, entries in items:
        if typ == "systempath":
            for e in entries:
                found = which(e)
                if found:
                    return found
        elif typ in ("staticpath",):
            found = first_existing(entries, is_dir=False)
            if found:
                return found
        elif typ in ("corepath",):
            found = first_existing(entries, is_dir=True)
            if found:
                return found
    for extra in EXTRA_EMU_PATHS.get(key, []):
        if extra.exists():
            return extra
        # App dir containing a binary of the same name
        if extra.is_dir():
            for cand in extra.rglob("*"):
                if cand.is_file() and os.access(cand, os.X_OK) and key.lower() in cand.name.lower():
                    return cand
    return None


def parse_systems_xml(path: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not path.exists():
        return out
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return out
    for s in root.iter("system"):
        name = (s.findtext("name") or "").strip()
        if not name:
            continue
        exts = (s.findtext("extension") or "").split()
        extset = {e.lower() if e.startswith(".") else f".{e.lower()}" for e in exts if e}
        cmds = []
        for c in s.findall("command"):
            label = (c.get("label") or "").strip() or "default"
            text = (c.text or "").strip()
            if text:
                cmds.append({"label": label, "template": text})
        path_t = (s.findtext("path") or f"%ROMPATH%/{name}").strip()
        out[name] = {
            "id": name,
            "name": (s.findtext("fullname") or name).strip(),
            "path_template": path_t,
            "extensions": sorted(extset),
            "commands": cmds,
            "theme": (s.findtext("theme") or name).strip(),
        }
    return out


def load_all_systems() -> dict[str, dict]:
    systems = parse_systems_xml(STOCK_SYSTEMS)
    # user dump in ~/ES-DE/es_systems.xml is ignored; ES-DE uses stock + custom_systems
    if CUSTOM_DIR.exists():
        # es_systems.xml first, then any other xml (e.g. zelda-twilight-princess.xml)
        files = []
        main = CUSTOM_DIR / "es_systems.xml"
        if main.exists():
            files.append(main)
        for p in sorted(CUSTOM_DIR.glob("*.xml")):
            if p.name.endswith(".bak") or p == main:
                continue
            files.append(p)
        for p in files:
            custom = parse_systems_xml(p)
            systems.update(custom)
    return systems


def parse_gamelist(path: Path) -> tuple[str | None, list[dict]]:
    """Return (alternative_emulator_label, games). Loose parse: ES-DE may put
    <alternativeEmulator> *before* <gameList>, which breaks a strict XML tree."""
    alt = None
    games: list[dict] = []
    if not path.exists():
        return alt, games
    text = path.read_text(errors="replace")
    m = re.search(r"<alternativeEmulator>\s*<label>([^<]+)</label>", text)
    if m:
        alt = m.group(1).strip()
    for block in re.findall(r"<game\b[^>]*>.*?</game>", text, flags=re.I | re.S):
        def tag(name: str) -> str | None:
            tm = re.search(rf"<{name}(?:\s[^>]*)?>(.*?)</{name}>", block, flags=re.I | re.S)
            if not tm:
                return None
            return re.sub(r"<[^>]+>", "", tm.group(1)).strip()

        gpath = tag("path")
        if not gpath:
            continue
        hidden = (tag("hidden") or "").lower() in {"true", "1", "yes"}
        fav = (tag("favorite") or "").lower() in {"true", "1", "yes"}
        games.append({
            "path": gpath,
            "name": tag("name") or Path(gpath).stem,
            "hidden": hidden,
            "favorite": fav,
            "image": tag("image") or tag("cover") or tag("thumbnail"),
        })
    return alt, games


def system_dir(sysinfo: dict, rom_root: Path) -> Path:
    raw = sysinfo["path_template"]
    raw = raw.replace("%ROMPATH%", str(rom_root))
    raw = raw.replace("%HOME%", str(HOME))
    return expand_user(raw)


def ext_ok(path: Path, extset: set[str]) -> bool:
    suf = path.suffix.lower()
    if suf in extset:
        return True
    # folders named like Foo.ps3dir
    if path.is_dir() and suf in extset:
        return True
    return False


def iter_roms(sysdir: Path, extset: set[str]) -> list[Path]:
    if not sysdir.exists():
        return []
    out: list[Path] = []
    try:
        entries = list(sysdir.iterdir())
    except OSError:
        return []
    for p in entries:
        if p.name.startswith("."):
            continue
        if p.name.lower() in SKIP_FILES:
            continue
        if p.is_dir() and p.name.lower() in MEDIA_SUBDIRS:
            continue
        if p.is_dir():
            if ext_ok(p, extset):
                out.append(p)
            continue
        if p.is_file() and ext_ok(p, extset):
            out.append(p)
    # prefer m3u/cue over bin of the same stem
    stems_m3u = {p.stem.lower() for p in out if p.suffix.lower() == ".m3u"}
    stems_cue = {p.stem.lower() for p in out if p.suffix.lower() == ".cue"}
    filtered = []
    for p in out:
        suf = p.suffix.lower()
        stem = p.stem.lower()
        if suf == ".bin" and (stem in stems_cue or stem in stems_m3u):
            continue
        if suf == ".cue" and stem in stems_m3u:
            continue
        filtered.append(p)
    return filtered


def cover_index(sysdir: Path) -> dict[str, Path]:
    idx: dict[str, Path] = {}
    for folder in ("covers", "miximages", "titlescreens", "screenshots"):
        d = sysdir / folder
        if not d.is_dir():
            continue
        try:
            files = list(d.iterdir())
        except OSError:
            continue
        for p in files:
            if not p.is_file():
                continue
            if p.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp", ".avif"}:
                continue
            key = p.stem.lower()
            # first folder wins (covers first)
            if key not in idx:
                idx[key] = p
    return idx


def find_cover(rom: Path, name: str, covers: dict[str, Path], listed_image: str | None, sysdir: Path) -> str | None:
    if listed_image:
        img = listed_image
        cand = Path(img) if img.startswith("/") else (sysdir / img)
        if cand.is_file():
            return str(cand)
    stem = rom.stem.lower()
    if stem in covers:
        return str(covers[stem])
    # loose: cover stem is a prefix/suffix of the rom stem or the gamelist name
    name_k = re.sub(r"\s+", " ", name).strip().lower()
    if name_k in covers:
        return str(covers[name_k])
    # try stripping bracket tags
    stripped = re.sub(r"\s*[\(\[][^\)\]]+[\)\]]", "", rom.stem).strip().lower()
    if stripped and stripped in covers:
        return str(covers[stripped])
    if name_k:
        for key, path in covers.items():
            if key.startswith(name_k) or name_k.startswith(key) or key.startswith(stripped) or stripped.startswith(key):
                return str(path)
    return None


def pick_default_label(sysinfo: dict, alt: str | None) -> str | None:
    labels = [c["label"] for c in sysinfo["commands"]]
    if alt and alt in labels:
        return alt
    # If the configured label isn't in the command list (e.g. typo), keep it
    # only when we can still find a close match.
    if alt:
        for lab in labels:
            if lab.lower() == alt.lower():
                return lab
    return labels[0] if labels else None


def emu_available(template: str, resolved: dict[str, str | None]) -> bool:
    # absolute path in the template?
    for m in re.finditer(r"(/(?:media|home|usr|opt|bin)[^\s]+)", template):
        p = Path(m.group(1))
        # strip trailing %ROM% leftovers already not in this regex
        if p.exists():
            return True
        # even if this one doesn't exist, other tokens might
    needed = re.findall(r"%EMULATOR_([A-Z0-9_+-]+)%", template)
    if not needed and not re.search(r"%CORE_RETROARCH%", template):
        # probably a hardcoded binary
        first = template.split()[0] if template.split() else ""
        first = first.replace("%ROM%", "").replace("%GAMEDIR%", "")
        if first.startswith("/"):
            return Path(first).exists()
        return True
    ok = True
    for n in needed:
        if not resolved.get(n):
            ok = False
            break
    if "%CORE_RETROARCH%" in template and not resolved.get("CORE_RETROARCH"):
        ok = False
    return ok


def build_index() -> dict:
    t0 = time.time()
    settings = parse_settings(ESDE / "settings" / "es_settings.xml")
    rom_root = Path(settings.get("ROMDirectory") or DEFAULT_ROM_ROOT)
    media_root = Path(settings.get("MediaDirectory") or str(rom_root))
    gamelist_root = DEFAULT_GAMELIST_ROOT
    rules = parse_find_rules(STOCK_RULES)
    systems = load_all_systems()

    # resolve commonly needed emulators once
    needed_names = set(EXTRA_EMU_PATHS) | {"RETROARCH", "OS-SHELL", "FLYCAST", "PPSSPP", "MELONDS", "XEMU", "MGBA", "CEMU", "PRIMEHACK"}
    resolved: dict[str, str | None] = {}
    for name in needed_names:
        p = resolve_named(name, rules)
        resolved[name] = str(p) if p else None
    core = resolve_named("RETROARCH", rules)
    # corepath specifically
    core_dir = None
    for typ, entries in (rules.get("RETROARCH") or rules.get("core:RETROARCH") or []):
        if typ == "corepath":
            core_dir = first_existing(entries, is_dir=True)
            if core_dir:
                break
    # parse_find_rules stored both emulator and core under same name last-write-wins.
    # Re-parse core path directly:
    if STOCK_RULES.exists():
        try:
            root = ET.parse(STOCK_RULES).getroot()
            for el in root:
                if el.tag == "core" and (el.get("name") or "") == "RETROARCH":
                    for rule in el:
                        if rule.get("type") == "corepath":
                            entries = [(e.text or "").strip() for e in rule if (e.text or "").strip()]
                            core_dir = first_existing(entries, is_dir=True) or core_dir
        except ET.ParseError:
            pass
    resolved["CORE_RETROARCH"] = str(core_dir) if core_dir else None
    if not resolved.get("RETROARCH"):
        p = which("retroarch")
        resolved["RETROARCH"] = str(p) if p else None
    if not resolved.get("OS-SHELL"):
        p = which("bash")
        resolved["OS-SHELL"] = str(p) if p else "/bin/bash"

    out_systems: list[dict] = []
    total_games = 0
    for sid, info in systems.items():
        sysdir = system_dir(info, rom_root)
        extset = set(info["extensions"])
        roms = iter_roms(sysdir, extset)
        gl_path = gamelist_root / sid / "gamelist.xml"
        # also try a gamelist next to the roms
        if not gl_path.exists():
            altp = sysdir / "gamelist.xml"
            if altp.exists():
                gl_path = altp
        alt_label, gl_games = parse_gamelist(gl_path)
        gl_by_name: dict[str, dict] = {}
        for g in gl_games:
            raw = g["path"].replace("\\", "/")
            gp = Path(raw)
            if not gp.is_absolute():
                gp = (sysdir / raw).resolve()
            else:
                gp = gp.resolve()
            gl_by_name[str(gp).lower()] = g
            gl_by_name[Path(raw).name.lower()] = g

        covers = cover_index(sysdir)
        # if MediaDirectory is the rom root, covers already live in sysdir/covers
        # also check downloaded_media fallback
        dm = DEFAULT_DOWNLOADED_MEDIA / sid
        if dm.exists():
            extra = cover_index(dm)
            for k, v in extra.items():
                covers.setdefault(k, v)

        games_out: list[dict] = []
        seen: set[str] = set()
        # Start from files on disk (ParseGamelistOnly is false)
        for rom in roms:
            key = str(rom.resolve()).lower()
            meta = gl_by_name.get(key) or gl_by_name.get(rom.name.lower())
            if meta and meta.get("hidden"):
                continue
            name = (meta or {}).get("name") or rom.stem
            cover = find_cover(rom, name, covers, (meta or {}).get("image"), sysdir)
            games_out.append({
                "name": name,
                "path": str(rom),
                "cover": cover,
                "favorite": bool((meta or {}).get("favorite")),
                "system": sid,
            })
            seen.add(key)

        # do not add gamelist-only missing files

        games_out.sort(key=lambda g: (not g["favorite"], g["name"].lower()))
        if not games_out:
            continue

        default_label = pick_default_label(info, alt_label)
        emus = []
        for c in info["commands"]:
            emus.append({
                "label": c["label"],
                "available": emu_available(c["template"], resolved),
                "default": c["label"] == default_label,
            })
        # if alt_label isn't in the list, still record it
        if alt_label and not any(e["label"] == alt_label for e in emus):
            emus.insert(0, {"label": alt_label, "available": False, "default": True})

        out_systems.append({
            "id": sid,
            "name": info["name"],
            "count": len(games_out),
            "dir": str(sysdir),
            "default_emulator": default_label,
            "emulators": emus,
            "games": games_out,
        })
        total_games += len(games_out)

    # sort systems by count desc then name, but keep a pleasant order for big ones
    out_systems.sort(key=lambda s: (-s["count"], s["name"].lower()))

    index = {
        "scanned_at": int(time.time()),
        "scan_ms": int((time.time() - t0) * 1000),
        "rom_directory": str(rom_root),
        "media_directory": str(media_root),
        "total_games": total_games,
        "resolved": {k: v for k, v in resolved.items() if v},
        "missing_emulators": sorted(k for k, v in resolved.items() if not v),
        "systems": out_systems,
    }
    return index


def main() -> int:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        index = build_index()
    except Exception as e:
        err = {"error": f"{type(e).__name__}: {e}", "systems": [], "total_games": 0}
        print(json.dumps(err, ensure_ascii=False))
        return 1
    tmp = CACHE_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
    tmp.replace(CACHE_FILE)
    print(json.dumps(index, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
