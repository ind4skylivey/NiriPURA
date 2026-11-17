#!/usr/bin/env python3
"""Parse niri keybinds.kdl -> JSON for the Quickshell cheatsheet.

Output: {"total": N, "groups": [{"name", "color", "items": [{"keys": [[..],..], "icon", "color", "label", "action"}]}]}
Rows with the same action inside a group are merged (e.g. Super+Left / Super+H).
"""
import json, os, re, sys

PATH = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.config/niri/modules/keybinds.kdl")
PALETTE = ["#ff2d78", "#00d4ff", "#d04dff", "#00ff41", "#ffb59f"]

KEYMAP = {
    "Mod": "Super", "Slash": "/", "Comma": ",", "Period": ".", "Semicolon": ";",
    "Grave": "`", "Minus": "-", "Equal": "=", "BracketLeft": "[", "BracketRight": "]",
    "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Escape": "Esc", "Delete": "Del",
    "Space": "Space", "Print": "PrtSc", "Return": "Enter", "Backslash": "\\", "Apostrophe": "'",
    "WheelScrollDown": "Rueda↓", "WheelScrollUp": "Rueda↑",
    "WheelScrollLeft": "Rueda←", "WheelScrollRight": "Rueda→",
    "XF86AudioRaiseVolume": "Vol+", "XF86AudioLowerVolume": "Vol-", "XF86AudioMute": "Mute",
    "XF86AudioMicMute": "MicMute", "XF86AudioPlay": "Play", "XF86AudioNext": "Next",
    "XF86AudioPrev": "Prev", "XF86MonBrightnessUp": "Bri+", "XF86MonBrightnessDown": "Bri-",
}
DIR = {"left": "←", "right": "→", "up": "↑", "down": "↓", "first": "inicio", "last": "final"}
ACTIONS = {
    "show-hotkey-overlay": "Lista de atajos (niri)",
    "close-window": "Cerrar ventana", "toggle-overview": "Overview",
    "screenshot": "Captura (selección)", "screenshot-screen": "Captura de pantalla",
    "screenshot-window": "Captura de ventana", "quit": "Salir de niri",
    "focus-workspace-previous": "Workspace anterior",
    "reset-window-height": "Restablecer alto", "switch-preset-window-height": "Alto preset",
    "switch-preset-column-width": "Ancho preset", "switch-preset-column-width-back": "Ancho preset (atrás)",
    "consume-window-into-column": "Meter ventana en columna",
    "expel-window-from-column": "Sacar ventana de columna",
    "maximize-column": "Maximizar columna", "fullscreen-window": "Pantalla completa",
    "maximize-window-to-edges": "Maximizar a los bordes",
    "expand-column-to-available-width": "Expandir columna", "center-column": "Centrar columna",
    "center-visible-columns": "Centrar columnas visibles",
    "toggle-window-floating": "Flotante ↔ tiling",
    "switch-focus-between-floating-and-tiling": "Foco flotante ↔ tiling",
    "toggle-keyboard-shortcuts-inhibit": "Inhibir atajos (on/off)",
    "toggle-column-tabbed-display": "Columna en pestañas",
    "focus-window-or-workspace-down": "Ventana o workspace ↓",
    "focus-window-or-workspace-up": "Ventana o workspace ↑",
    "power-off-monitors": "Apagar monitores", "toggle-window-rule-opacity": "Opacidad on/off",
}

def human_action(action):
    a = action.strip().rstrip(";").strip()
    m = re.match(r'([\w-]+)\s*(.*)', a)
    name, args = m.group(1), m.group(2).strip()
    argv = re.findall(r'"((?:[^"\\]|\\.)*)"|(\S+)', args)
    argv = [x or y for x, y in argv]
    if name in ("spawn", "spawn-sh"):
        cmd = argv[0] if argv else ""
        words = cmd.split() if name == "spawn-sh" or len(argv) == 1 else argv
        prog = os.path.basename(os.path.expandvars(words[0])) if words else "?"
        rest = words[1:]
        if prog == "noctalia" and len(rest) >= 3 and rest[1] == "panel-toggle":
            return "Noctalia: " + rest[2].split("/")[-1].split(":")[0].replace("-", " ")
        if prog == "omarchy-link" and len(rest) >= 2:
            v = rest[1]
            if rest[0] == "launch":
                segs = v.split(".")
                v = segs[1] if len(segs) > 1 and segs[0] == "com" else segs[-1]
            return "OmarchyTV: " + v.replace("_", " ").replace(".", " ")
        if prog == "wpctl" and "SOURCE" in cmd:
            return "Mic mute"
        if prog.endswith(".sh"):
            prog = prog[:-3]
        return prog.replace("-", " ").replace("_", " ")
    if name in ACTIONS:
        lbl = ACTIONS[name]
        if name == "screenshot-screen" and "write-to-disk=false" in args:
            lbl += " (al portapapeles)"
        return lbl
    if name in ("focus-workspace", "move-column-to-workspace", "move-window-to-workspace"):
        pre = {"focus-workspace": "Workspace", "move-column-to-workspace": "Columna → workspace",
               "move-window-to-workspace": "Ventana → workspace"}[name]
        return f"{pre} {args.strip()}".strip()
    if name in ("set-column-width", "set-window-height"):
        return ("Ancho columna " if "width" in name else "Alto ventana ") + (argv[0] if argv else "")
    parts = name.split("-")
    d = parts[-1]
    if d in DIR:
        base = "-".join(parts[:-1])
        table = {
            "focus-column": "Foco columna", "focus-window": "Foco ventana", "focus-monitor": "Foco monitor",
            "move-column": "Mover columna", "move-window": "Mover ventana",
            "focus-workspace": "Workspace", "move-workspace": "Mover workspace",
            "move-column-to-workspace": "Columna → workspace",
            "move-window-to-workspace": "Ventana → workspace",
            "move-column-to-monitor": "Columna → monitor", "move-window-to-monitor": "Ventana → monitor",
            "move-workspace-to-monitor": "WS → monitor",
            "consume-or-expel-window": "Meter/sacar ventana", "move-column-to": "Columna al",
            "focus-column-or-monitor": "Columna o monitor",
        }
        word = {"move-workspace-to-monitor": {"left": "izq", "right": "der", "up": "arriba", "down": "abajo"}}
        if base in word:
            return f"{table[base]} {word[base][d]}"
        if base in table:
            return f"{table[base]} {DIR[d]}"
    return name.replace("-", " ").capitalize()

def parse_title(t):
    if t is None:
        return None
    color = None
    m = re.search(r"<span[^>]*foreground=['\"]([^'\"]+)['\"][^>]*>(.*?)</span>", t)
    icon = ""
    if m:
        color, icon = m.group(1), re.sub(r"<[^>]+>", "", m.group(2)).strip()
        rest = t[:m.start()] + t[m.end():]
    else:
        rest = t
    label = re.sub(r"<[^>]+>", "", rest)
    label = label.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").strip()
    return {"icon": icon, "color": color, "label": label}

def fmt_keys(k):
    return [KEYMAP.get(p, p) for p in k.split("+")]

BIND = re.compile(r'^\s*(?P<key>[A-Za-z0-9_+]+)\s+(?P<props>[^{]*?)\s*\{\s*(?P<action>.*?)\s*\}\s*(//.*)?$')
BIND_NOPROPS = re.compile(r'^\s*(?P<key>[A-Za-z0-9_+]+)\s*\{\s*(?P<action>.*?)\s*\}\s*(//.*)?$')
TITLE = re.compile(r'hotkey-overlay-title=(null|"((?:[^"\\]|\\.)*)")')

def compact_paren(name):
    """Keep a short parenthetical so long section titles stay distinct."""
    m = re.search(r"^(.*?)\s*\(([^)]+)\)\s*$", name)
    if not m:
        return name
    base, inner = m.group(1).strip(), m.group(2).strip()
    token = re.split(r"\s*=\s*|\s*,\s*|\s*;\s*", inner)[0].strip()
    if len(token) > 16:
        token = token[:14].rstrip(" /-,") + "…"
    return f"{base} ({token})"


def display_names(raw_names, limit=26):
    """Shorten long titles, but never collide two different section names."""
    disp = []
    for name in raw_names:
        if len(name) > limit:
            disp.append(re.sub(r"\s*\(.*?\)\s*", " ", name).strip() or name)
        else:
            disp.append(name)
    buckets = {}
    for i, n in enumerate(disp):
        buckets.setdefault(n, []).append(i)
    for n, idxs in buckets.items():
        if len(idxs) < 2:
            continue
        for i in idxs:
            disp[i] = compact_paren(raw_names[i])
        if len({disp[i] for i in idxs}) < len(idxs):
            for i in idxs:
                disp[i] = raw_names[i]
    return disp


def main():
    lines = open(PATH, encoding="utf-8").read().splitlines()
    groups, cur = [], None
    total = 0
    in_banner = False
    seen_binds = False

    def new_group(name):
        nonlocal cur
        cur = {"name": name.strip(), "items": [], "_by": {}}
        groups.append(cur)

    def add_item(m, disabled=False):
        nonlocal total
        key, action = m.group("key"), m.group("action").rstrip(";").strip()
        props = m.groupdict().get("props") or ""
        tm = TITLE.search(props)
        title = None
        if tm and tm.group(1) != "null":
            title = parse_title(tm.group(2).encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
        if cur is None:
            new_group("Cheatsheet")
        total += 1
        label = title["label"] if title else human_action(action)
        mergekey = (label, action, disabled)
        if mergekey in cur["_by"]:
            cur["_by"][mergekey]["keys"].append(fmt_keys(key))
            return
        item = {"keys": [fmt_keys(key)], "icon": title["icon"] if title else "",
                "color": (title or {}).get("color"), "label": label, "action": action,
                "custom": bool(title), "disabled": disabled}
        cur["_by"][mergekey] = item
        cur["items"].append(item)

    prev_blank = True
    for raw in lines:
        s = raw.strip()
        if s.startswith("//"):
            body = s[2:].strip()
            if re.match(r"^=+$", body):
                in_banner = not in_banner
                prev_blank = True
                continue
            if in_banner:
                if seen_binds:  # banner heading, e.g. "MONITOR FOCUS -- Mod+... (no overlay)"
                    name = re.split(r"\s+--\s+", body)[0].strip()
                    new_group(name.title() if name.isupper() else name)
                continue
            if "{" in body and "}" in body:
                # Commented-out bind: show it dimmed if it still parses as a real bind.
                mdis = BIND.match(body) or BIND_NOPROPS.match(body)
                if mdis:
                    add_item(mdis, disabled=True)
                prev_blank = False
                continue
            m = re.match(r"^-{2,}\s*(.*?)\s*-{2,}$", body)
            if m:
                new_group(m.group(1))
            elif prev_blank:
                new_group(body)
            prev_blank = False
            continue
        prev_blank = (s == "")
        if s == "binds {":
            seen_binds = True
        if s in ("", "binds {", "}"):
            continue
        m = BIND.match(raw) or BIND_NOPROPS.match(raw)
        if not m:
            continue
        add_item(m, disabled=False)

    kept = [g for g in groups if g["items"]]
    names = display_names([g["name"] for g in kept])
    out = []
    for g, name in zip(kept, names):
        out.append({"name": name, "items": g["items"]})
    # merge empty-named / tiny dup group names
    for i, g in enumerate(out):
        g["color"] = PALETTE[i % len(PALETTE)]
        # collapse numeric runs: Super+1..0 with action "X n"
        items, res, i2 = g["items"], [], 0
        while i2 < len(items):
            it = items[i2]
            mm = re.match(r"^(.*\D)(\d+)$", it["label"])
            run = [it]
            if mm and not it["custom"] and len(it["keys"]) == 1:
                j = i2 + 1
                while j < len(items):
                    m2 = re.match(r"^(.*\D)(\d+)$", items[j]["label"])
                    if m2 and m2.group(1) == mm.group(1) and len(items[j]["keys"]) == 1 and items[j]["keys"][0][:-1] == it["keys"][0][:-1]:
                        run.append(items[j]); j += 1
                    else:
                        break
            if len(run) >= 3:
                first, last = run[0], run[-1]
                lbl = mm.group(1) + mm.group(2) + "–" + re.match(r"^.*\D(\d+)$", last["label"]).group(1)
                res.append({"keys": [first["keys"][0][:-1] + [first["keys"][0][-1] + "…" + last["keys"][0][-1]]],
                            "icon": "", "color": None, "label": lbl,
                            "action": " / ".join(r["action"] for r in run), "custom": False,
                            "disabled": first.get("disabled", False), "count": len(run)})
                i2 += len(run)
            else:
                res.append(it); i2 += 1
        g["items"] = res
    json.dump({"total": total, "file": PATH, "groups": out}, sys.stdout, ensure_ascii=False)

if __name__ == "__main__":
    main()
