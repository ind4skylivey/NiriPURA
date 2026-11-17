#!/usr/bin/env python3
"""Launch a game with the same command ES-DE would use. Read-only wrt ES-DE files."""
from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

# Reuse resolver + system merge from the scanner.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from scan_esde import (  # noqa: E402
    CUSTOM_DIR, ESDE, STOCK_RULES, STOCK_SYSTEMS,
    DEFAULT_GAMELIST_ROOT, DEFAULT_ROM_ROOT,
    expand_user, first_existing, load_all_systems, parse_find_rules,
    parse_gamelist, parse_settings, resolve_named, system_dir, which,
    EXTRA_EMU_PATHS,
)

INJECT_RE = re.compile(r"%INJECT%=(\S+)")
STARTDIR_RE = re.compile(r"%STARTDIR%=(\S+)")
FLAG_TOKENS = {"%ENABLESHORTCUTS%", "%RUNINBACKGROUND%"}


def resolve_all(rules) -> dict[str, str]:
    names = set(EXTRA_EMU_PATHS) | {
        "RETROARCH", "OS-SHELL", "FLYCAST", "PPSSPP", "MELONDS", "XEMU",
        "MGBA", "CEMU", "PRIMEHACK", "DOLPHIN", "PCSX2", "DUCKSTATION",
        "EDEN", "RYUJINX", "RPCS3", "AZAHAR", "REDREAM", "DUSK",
    }
    out: dict[str, str] = {}
    for n in names:
        p = resolve_named(n, rules)
        if p:
            out[n] = str(p)
    if "RETROARCH" not in out:
        p = which("retroarch")
        if p:
            out["RETROARCH"] = str(p)
    if "OS-SHELL" not in out:
        p = which("bash")
        out["OS-SHELL"] = str(p) if p else "/bin/bash"
    # core path
    if STOCK_RULES.exists():
        import xml.etree.ElementTree as ET
        try:
            root = ET.parse(STOCK_RULES).getroot()
            for el in root:
                if el.tag == "core" and (el.get("name") or "") == "RETROARCH":
                    for rule in el:
                        if rule.get("type") == "corepath":
                            entries = [(e.text or "").strip() for e in rule if (e.text or "").strip()]
                            core = first_existing(entries, is_dir=True)
                            if core:
                                out["CORE_RETROARCH"] = str(core)
        except ET.ParseError:
            pass
    return out


def pick_command(sysinfo: dict, alt_label: str | None, requested: str | None) -> dict:
    cmds = sysinfo["commands"]
    if not cmds:
        raise SystemExit(f"sin comandos de emulador para {sysinfo['id']}")
    labels = {c["label"]: c for c in cmds}

    def find(label: str | None):
        if not label:
            return None
        if label in labels:
            return labels[label]
        for lab, c in labels.items():
            if lab.lower() == label.lower():
                return c
        return None

    return find(requested) or find(alt_label) or cmds[0]


def desktop_exec(path: Path) -> list[str] | None:
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        if line.startswith("Exec="):
            raw = line[5:].strip()
            raw = re.sub(r"\s+%[fFuUdDnNickvm]\b", "", raw)
            try:
                return shlex.split(raw)
            except ValueError:
                return [raw]
    return None


def substitute(template: str, *, rom: Path, resolved: dict[str, str], rom_root: Path) -> tuple[str, Path | None]:
    start_dir = None
    def repl_emu(m):
        name = m.group(1)
        path = resolved.get(name)
        return path or m.group(0)

    # STARTDIR / INJECT need BASENAME first
    basename = rom.stem
    filename = rom.name
    gamedir = str(rom.parent)
    text = template
    text = text.replace("%ROM%", str(rom))
    text = text.replace("%BASENAME%", basename)
    text = text.replace("%FILENAME%", filename)
    text = text.replace("%GAMEDIR%", gamedir)
    text = text.replace("%ROMPATH%", str(rom_root))
    text = text.replace("%HOME%", str(Path.home()))
    text = re.sub(r"%EMULATOR_([A-Z0-9_+-]+)%", repl_emu, text)
    if "%CORE_RETROARCH%" in text:
        core = resolved.get("CORE_RETROARCH", "")
        text = text.replace("%CORE_RETROARCH%", core)
    # EMUDIR is the emulator binary's directory (first existing absolute in the line)
    emudir = ""
    for tok in text.split():
        if tok.startswith("/") and Path(tok).exists():
            emudir = str(Path(tok).parent)
            break
    text = text.replace("%EMUDIR%", emudir)

    m = STARTDIR_RE.search(text)
    if m:
        start_dir = expand_user(m.group(1))
        text = STARTDIR_RE.sub("", text)
    # drop INJECT if the inject file does not exist; otherwise leave a marker
    def drop_or_keep(mo):
        inject_file = expand_user(mo.group(1))
        if not inject_file.is_absolute():
            inject_file = rom.parent / mo.group(1)
        if inject_file.is_file():
            # ES-DE would splice file contents; we skip contents to stay simple
            return ""
        return ""
    text = INJECT_RE.sub(drop_or_keep, text)
    for flag in FLAG_TOKENS:
        text = text.replace(flag, "")
    text = re.sub(r"\s+", " ", text).strip()
    return text, start_dir


def launch(argv_cmd: list[str], cwd: Path | None) -> None:
    env = os.environ.copy()
    local = str(Path.home() / ".local/bin")
    env["PATH"] = local + os.pathsep + env.get("PATH", "")
    log_dir = Path.home() / ".cache" / "asus-panels"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = open(log_dir / "launch.log", "a", encoding="utf-8")
    log.write(f"+ cwd={cwd} cmd={argv_cmd}\n")
    log.flush()
    subprocess.Popen(
        argv_cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--system", required=True)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--emulator", default="")
    args = ap.parse_args()

    rom = Path(args.rom)
    if not rom.exists():
        print(f"no existe: {rom}", file=sys.stderr)
        return 2

    settings = parse_settings(ESDE / "settings" / "es_settings.xml")
    rom_root = Path(settings.get("ROMDirectory") or DEFAULT_ROM_ROOT)
    systems = load_all_systems()
    info = systems.get(args.system)
    if not info:
        print(f"sistema desconocido: {args.system}", file=sys.stderr)
        return 2

    sysdir = system_dir(info, rom_root)
    gl = DEFAULT_GAMELIST_ROOT / args.system / "gamelist.xml"
    alt, _ = parse_gamelist(gl)
    cmd = pick_command(info, alt, args.emulator or None)
    rules = parse_find_rules(STOCK_RULES)
    resolved = resolve_all(rules)
    text, start_dir = substitute(cmd["template"], rom=rom, resolved=resolved, rom_root=rom_root)

    # leftover unresolved %EMULATOR_% ?
    miss = re.findall(r"%EMULATOR_([A-Z0-9_+-]+)%", text)
    if miss:
        print(f"no encuentro el emulador {', '.join(miss)}", file=sys.stderr)
        return 3
    if "%CORE_RETROARCH%" in text:
        print("no encuentro los cores de RetroArch", file=sys.stderr)
        return 3

    try:
        argv_cmd = shlex.split(text)
    except ValueError:
        argv_cmd = text.split()
    if not argv_cmd:
        print("comando vacío", file=sys.stderr)
        return 3

    # .desktop shortcuts: prefer gio launch / parsed Exec
    if rom.suffix.lower() == ".desktop" or argv_cmd[-1].endswith(".desktop"):
        desk = rom if rom.suffix.lower() == ".desktop" else Path(argv_cmd[-1])
        exe = desktop_exec(desk)
        if exe:
            argv_cmd = exe
        else:
            gio = which("gio")
            if gio:
                argv_cmd = [str(gio), "launch", str(desk)]

    cwd = start_dir if start_dir and start_dir.exists() else rom.parent
    launch(argv_cmd, cwd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
