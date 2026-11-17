#!/usr/bin/env python3
"""S1B.CMD runner — lists or executes palette commands.

Never prints secrets. sudo always opens in a kitty window so the user
types their password themselves.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOML = HERE / "commands.toml"
HOME = Path.home()
HD2 = Path(os.environ.get("NIRIPURA_HD2", "/media/il1v3y/HD2"))
PACMAN_CACHE = Path("/var/cache/pacman/pkg")
THUMBNAILS = HOME / ".cache" / "thumbnails"
PARU_CACHE = HOME / ".cache" / "paru"
YAY_CACHE = HOME / ".cache" / "yay"
STEAM_SHADER = HOME / ".local/share/Steam/steamapps/shadercache"
STEAM_SHADER_ALT = HOME / ".steam/steam/steamapps/shadercache"
VALHEIM = HOME / ".config/unity3d/IronGate/Valheim"
GAME_SAFE = HD2 / "backups" / "game-safe"
ASUS_TOGGLE = HOME / ".config/quickshell/asus-panels/toggle.sh"

# Conservative, known save locations only. Add more later as they are verified.
SAVE_LOCS = [
    {"name": "Valheim", "path": VALHEIM},
]


def out(*parts, **kw) -> None:
    print(*parts, **kw)
    sys.stdout.flush()


def load_commands() -> list[dict]:
    import tomllib

    data = tomllib.loads(TOML.read_text(encoding="utf-8"))
    cmds = []
    for c in data.get("commands", []):
        cmds.append(
            {
                "id": c["id"],
                "name": c.get("name", c["id"]),
                "icon": c.get("icon", "󰘳"),
                "group": c.get("group", "otros"),
                "help": c.get("help", ""),
                "builtin": c.get("builtin", ""),
                "cmd": c.get("cmd", ""),
                "confirm": bool(c.get("confirm", False)),
                "danger": bool(c.get("danger", False)),
                "sudo": bool(c.get("sudo", False)),
            }
        )
    return cmds


def find_cmd(cid: str) -> dict:
    for c in load_commands():
        if c["id"] == cid:
            return c
    raise SystemExit(f"comando desconocido: {cid}")


def run_cmd(argv: list[str], timeout: int | None = None, check: bool = False) -> int:
    try:
        p = subprocess.run(
            argv,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except FileNotFoundError:
        out(f"(no está instalado: {argv[0]})")
        return 127
    except subprocess.TimeoutExpired as e:
        if e.stdout:
            sys.stdout.write(e.stdout if isinstance(e.stdout, str) else e.stdout.decode())
        out(f"(cortado a {timeout}s)")
        return 124
    if p.stdout:
        sys.stdout.write(p.stdout)
        if not p.stdout.endswith("\n"):
            sys.stdout.write("\n")
        sys.stdout.flush()
    if check and p.returncode != 0:
        raise SystemExit(p.returncode)
    return p.returncode


def human(n: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    x = float(max(0, n))
    for u in units:
        if x < 1024 or u == units[-1]:
            if u == "B":
                return f"{int(x)} {u}"
            return f"{x:.1f} {u}"
        x /= 1024
    return f"{x:.1f} TiB"


def path_size(p: Path) -> int:
    if not p.exists():
        return 0
    try:
        r = subprocess.run(
            ["du", "-sb", "-x", "--apparent-size", str(p)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=25,
        )
        if r.returncode == 0 and r.stdout:
            return int(r.stdout.split()[0])
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        pass
    # fallback without apparent-size (btrfs-friendly disk usage)
    try:
        r = subprocess.run(
            ["du", "-sb", "-x", str(p)],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=25,
        )
        if r.returncode == 0 and r.stdout:
            return int(r.stdout.split()[0])
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        pass
    return 0


def resolve_shader() -> Path | None:
    for p in (STEAM_SHADER, STEAM_SHADER_ALT):
        if p.exists():
            try:
                return p.resolve()
            except OSError:
                return p
    return None


def kitty_sudo(cmd: str, title: str) -> int:
    kitty = shutil.which("kitty")
    if not kitty:
        out("No encontré kitty. Abre una terminal y corre:")
        out(f"  {cmd}")
        return 1
    out(f"Abro kitty para que escribas tu contraseña de sudo.")
    out(f"Comando: {cmd}")
    wrapped = (
        f"{cmd}; ec=$?; echo; "
        f'echo "[listo — pulsa Enter para cerrar]"; read; exit $ec'
    )
    try:
        subprocess.Popen(
            [kitty, "--title", title, "-e", "bash", "-lc", wrapped],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError as e:
        out(f"No pude abrir kitty: {e}")
        return 1
    return 0


# ── builtins ──────────────────────────────────────────────────────────────




def du_children(roots: list[Path], timeout: int = 10) -> None:
    """Size first-level children of each root in one parallel wave."""
    skip_root = {"proc", "sys", "dev", "run"}
    jobs: list[tuple[Path, Path, subprocess.Popen]] = []
    timeout_bin = shutil.which("timeout")
    for root in roots:
        if not root.exists():
            continue
        try:
            kids = []
            for child in root.iterdir():
                try:
                    if root == Path("/") and child.name in skip_root:
                        continue
                    if child.is_symlink():
                        continue
                    if child.is_dir() or child.is_file():
                        kids.append(child)
                except OSError:
                    continue
        except OSError as e:
            out(f"(sin permiso: {e})")
            continue
        if not kids:
            out("(vacío)")
            continue
        for child in kids:
            argv = ["du", "-xsh", str(child)]
            if timeout_bin:
                argv = [timeout_bin, "--preserve-status", str(timeout), *argv]
            jobs.append(
                (
                    root,
                    child,
                    subprocess.Popen(
                        argv,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        text=True,
                    ),
                )
            )
    if not jobs:
        return
    by_root: dict[Path, list[str]] = {r: [] for r in roots}
    deadline = time.time() + timeout + 3
    for root, child, proc in jobs:
        remain = max(0.2, deadline - time.time())
        try:
            stdout, _ = proc.communicate(timeout=remain)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            by_root.setdefault(root, []).append(f"(corte)\t{child}")
            continue
        line = (stdout or "").strip()
        if line:
            by_root.setdefault(root, []).append(line.splitlines()[0])
        else:
            by_root.setdefault(root, []).append(f"(corte)\t{child}")
    for root in roots:
        out(f"-- {root} --")
        if not root.exists():
            out("(no existe)")
            continue
        rows = by_root.get(root) or []
        if not rows:
            out("(sin datos o sin permiso)")
            continue
        sized = [r for r in rows if not r.startswith("(corte)")]
        cuts = [r for r in rows if r.startswith("(corte)")]
        s = subprocess.run(
            ["sort", "-hr"],
            input="\n".join(sized) + "\n",
            stdout=subprocess.PIPE,
            text=True,
        )
        for ln in s.stdout.splitlines()[:14]:
            out(ln)
        for ln in cuts:
            out(ln)


def builtin_espacio() -> int:
    out("== discos ==")
    targets = ["/"]
    if HD2.exists():
        targets.append(str(HD2))
    run_cmd(["df", "-h", *targets])
    out()
    out("== tipo de sistema de archivos ==")
    for t in targets:
        run_cmd(["findmnt", "-no", "FSTYPE,TARGET,OPTIONS", t])
    out()
    out("== compresión ==")
    fstype = subprocess.run(
        ["findmnt", "-no", "FSTYPE", "/"],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    if fstype == "btrfs":
        out("/ está en btrfs (puede tener compresión).")
        out("df muestra espacio en disco, no el tamaño descomprimido.")
        if shutil.which("compsize"):
            out()
            run_cmd(["compsize", "-x", "/"], timeout=20)
        else:
            out("Para ver el ratio instala el paquete 'compsize'.")
    else:
        out(f"/ está en {fstype or 'desconocido'}.")
    if HD2.exists():
        hd2t = subprocess.run(
            ["findmnt", "-no", "FSTYPE", str(HD2)],
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        out(f"HD2 está en {hd2t or 'desconocido'}" + (", sin compresión." if hd2t == "ext4" else "."))
    else:
        out("HD2 no está montado.")
    out()
    out("== carpetas que más ocupan (1 nivel, en paralelo, tope 10s c/u) ==")
    roots = [Path("/"), HOME]
    if HD2.exists():
        roots.append(HD2)
    du_children(roots, timeout=10)
    return 0


def builtin_estado() -> int:
    out("== updates pendientes ==")
    if shutil.which("checkupdates"):
        try:
            p = subprocess.run(
                ["checkupdates"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            pkgs = [ln for ln in p.stdout.splitlines() if ln.strip()]
            out(f"{len(pkgs)} paquete(s) con update.")
            for ln in pkgs[:25]:
                out("  " + ln)
            if len(pkgs) > 25:
                out(f"  … y {len(pkgs) - 25} más")
        except subprocess.TimeoutExpired:
            out("(checkupdates tardó demasiado)")
    else:
        out("(checkupdates no está instalado)")
    out()
    out("== servicios caídos (system) ==")
    run_cmd(["systemctl", "--failed", "--no-pager", "--legend=no"])
    out()
    out("== servicios caídos (usuario) ==")
    run_cmd(["systemctl", "--user", "--failed", "--no-pager", "--legend=no"])
    out()
    out("== temperaturas ==")
    if shutil.which("sensors"):
        run_cmd(["sensors"], timeout=8)
    else:
        out("(sensors no está instalado)")
    return 0


def _cache_rows() -> list[tuple[str, Path | None, int, str]]:
    shader = resolve_shader()
    rows = [
        ("paru", PARU_CACHE, path_size(PARU_CACHE) if PARU_CACHE.exists() else 0,
         "existe" if PARU_CACHE.exists() else "no existe"),
        ("yay", YAY_CACHE, path_size(YAY_CACHE) if YAY_CACHE.exists() else 0,
         "existe" if YAY_CACHE.exists() else "no existe"),
        ("pacman", PACMAN_CACHE, path_size(PACMAN_CACHE) if PACMAN_CACHE.exists() else 0,
         "existe" if PACMAN_CACHE.exists() else "no existe"),
        ("thumbnails", THUMBNAILS, path_size(THUMBNAILS) if THUMBNAILS.exists() else 0,
         "existe" if THUMBNAILS.exists() else "no existe"),
        ("steam shadercache", shader, path_size(shader) if shader else 0,
         str(shader) if shader else "no existe"),
    ]
    return rows


def builtin_cache_dry() -> int:
    out("== cachés regenerables (simulación, no se borra nada) ==")
    total = 0
    for name, path, size, note in _cache_rows():
        total += size
        loc = str(path) if path else "—"
        out(f"{human(size):>10}  {name}")
        out(f"            {loc}  ({note})")
    out()
    out(f"total aproximado: {human(total)}")
    out()
    out("== paccache -d (qué se borraría, conserva 3 versiones) ==")
    if shutil.which("paccache"):
        # -d dry run, -v verbose, -k 3 keep last 3 (paccache default is 3)
        run_cmd(["paccache", "-d", "-v", "-k", "3"], timeout=40)
    else:
        out("(paccache no está instalado; es parte de pacman-contrib)")
    out()
    out("Para borrar de verdad usa las entradas rojas, cada una con confirmación.")
    return 0


def _rm_tree_contents(path: Path, what: str) -> int:
    if not path.exists():
        out(f"{what}: no existe ({path})")
        return 0
    before = path_size(path)
    out(f"Borrando {what} ({human(before)})")
    out(f"  {path}")
    # Prefer emptying the directory rather than deleting the root folder
    if path.is_file() or path.is_symlink():
        try:
            path.unlink()
        except OSError as e:
            out(f"no pude borrar: {e}")
            return 1
    else:
        for child in path.iterdir():
            try:
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            except OSError as e:
                out(f"  omití {child.name}: {e}")
    after = path_size(path) if path.exists() else 0
    out(f"listo. quedó {human(after)}")
    return 0


def builtin_cache_paru() -> int:
    if not PARU_CACHE.exists():
        out(f"No hay caché de paru en {PARU_CACHE}")
        return 0
    return _rm_tree_contents(PARU_CACHE, "caché de paru")


def builtin_cache_thumbnails() -> int:
    if not THUMBNAILS.exists():
        out(f"No hay miniaturas en {THUMBNAILS}")
        return 0
    return _rm_tree_contents(THUMBNAILS, "miniaturas")


def builtin_cache_shaders() -> int:
    shader = resolve_shader()
    if not shader:
        out("No encontré steamapps/shadercache")
        return 0
    return _rm_tree_contents(shader, "shader cache de Steam")


def _restart_user(unit: str) -> int:
    out(f"Reiniciando {unit} …")
    rc = run_cmd(["systemctl", "--user", "restart", unit], timeout=20)
    run_cmd(["systemctl", "--user", "is-active", unit], timeout=5)
    run_cmd(["systemctl", "--user", "status", unit, "--no-pager", "-n", "8"], timeout=8)
    return rc


def builtin_restart_noctalia() -> int:
    return _restart_user("noctalia.service")


def builtin_restart_omarchy() -> int:
    return _restart_user("omarchy-link.service")


def builtin_restart_voxtype() -> int:
    return _restart_user("voxtype.service")


def builtin_restart_mpd() -> int:
    return _restart_user("mpd.service")


def builtin_restart_asus() -> int:
    script = str(ASUS_TOGGLE)
    if not ASUS_TOGGLE.exists():
        out(f"No está {script}")
        return 1
    out("Deteniendo paneles ASUS …")
    run_cmd(["bash", script, "stop"], timeout=8)
    time.sleep(0.4)
    out("Arrancando paneles ASUS …")
    rc = run_cmd(["bash", script, "start"], timeout=8)
    out("listo." if rc == 0 else f"start salió con {rc}")
    return rc


def builtin_niri_validate() -> int:
    out("niri validate …")
    return run_cmd(["niri", "validate"], timeout=15)


def builtin_niri_reload() -> int:
    out("niri validate …")
    rc = run_cmd(["niri", "validate"], timeout=15)
    if rc != 0:
        out("validación falló: no recargo la config.")
        return rc
    out("recargando (niri msg action load-config-file) …")
    rc = run_cmd(["niri", "msg", "action", "load-config-file"], timeout=10)
    out("config recargada." if rc == 0 else f"reload salió con {rc}")
    return rc


def builtin_saves_list() -> int:
    out("== partidas conocidas (solo lista) ==")
    if not HD2.exists():
        out("aviso: HD2 no está montado; el respaldo no se podría escribir.")
    out(f"destino: {GAME_SAFE}/<fecha>-quick/")
    out()
    total = 0
    for item in SAVE_LOCS:
        p: Path = item["path"]
        if p.exists():
            sz = path_size(p)
            total += sz
            out(f"  {item['name']}: {human(sz)}")
            out(f"    {p}")
        else:
            out(f"  {item['name']}: no está")
            out(f"    {p}")
    out()
    out(f"total: {human(total)}")
    out("Por ahora solo Valheim (ruta ya usada en respaldos anteriores).")
    out("Para copiar usa 'Respaldar partidas' y confirma.")
    return 0


def builtin_saves_backup() -> int:
    if not HD2.exists():
        out("HD2 no está montado. No copio nada.")
        return 1
    dest = GAME_SAFE / f"{date.today().isoformat()}-quick"
    dest.mkdir(parents=True, exist_ok=True)
    out(f"destino: {dest}")
    rc = 0
    copied = 0
    for item in SAVE_LOCS:
        p: Path = item["path"]
        name = item["name"]
        if not p.exists():
            out(f"  omito {name}: no está ({p})")
            continue
        target = dest / name
        out(f"  {name} → {target}")
        if not shutil.which("rsync"):
            out("rsync no está instalado")
            return 1
        # trailing slash: copy contents into target/
        r = subprocess.run(
            ["rsync", "-a", "--info=stats2,progress2", f"{p}/", f"{target}/"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
        if r.stdout:
            sys.stdout.write(r.stdout)
            if not r.stdout.endswith("\n"):
                sys.stdout.write("\n")
            sys.stdout.flush()
        if r.returncode != 0:
            out(f"  rsync salió con {r.returncode}")
            rc = r.returncode
        else:
            copied += 1
            out(f"  ok ({human(path_size(target))})")
    out(f"listo. {copied} juego(s) en {dest}")
    return rc


BUILTINS = {
    "espacio": builtin_espacio,
    "estado": builtin_estado,
    "cache_dry": builtin_cache_dry,
    "cache_paru": builtin_cache_paru,
    "cache_thumbnails": builtin_cache_thumbnails,
    "cache_shaders": builtin_cache_shaders,
    "restart_noctalia": builtin_restart_noctalia,
    "restart_omarchy": builtin_restart_omarchy,
    "restart_voxtype": builtin_restart_voxtype,
    "restart_mpd": builtin_restart_mpd,
    "restart_asus": builtin_restart_asus,
    "niri_validate": builtin_niri_validate,
    "niri_reload": builtin_niri_reload,
    "saves_list": builtin_saves_list,
    "saves_backup": builtin_saves_backup,
}


def execute(entry: dict, yes: bool) -> int:
    if (entry["confirm"] or entry["danger"] or entry["sudo"]) and not yes:
        out("Este comando pide confirmación. Lánzalo otra vez con --yes desde la paleta.")
        return 2
    if entry["sudo"] or (entry.get("cmd") or "").strip().startswith("sudo "):
        return kitty_sudo(entry["cmd"], f"S1B.CMD · {entry['name']}")
    if entry["builtin"]:
        fn = BUILTINS.get(entry["builtin"])
        if not fn:
            out(f"builtin desconocido: {entry['builtin']}")
            return 1
        return fn()
    cmd = (entry.get("cmd") or "").strip()
    if not cmd:
        out("este comando no tiene builtin ni cmd")
        return 1
    out(f"$ {cmd}")
    return run_cmd(["bash", "-lc", cmd], timeout=180)


def main() -> int:
    ap = argparse.ArgumentParser(description="S1B.CMD runner")
    ap.add_argument("--list", action="store_true", help="imprimir el catálogo en JSON")
    ap.add_argument("--run", metavar="ID", help="ejecutar un comando por id")
    ap.add_argument("--yes", action="store_true", help="confirmación ya dada por la UI")
    args = ap.parse_args()
    if args.list:
        json.dump({"commands": load_commands()}, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0
    if args.run:
        return execute(find_cmd(args.run), yes=args.yes)
    ap.print_help()
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        raise SystemExit(0)
    except KeyboardInterrupt:
        raise SystemExit(130)
