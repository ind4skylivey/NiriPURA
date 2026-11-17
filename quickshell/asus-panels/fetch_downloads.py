#!/usr/bin/env python3
"""Read-only snapshot of qBittorrent + Nicotine+ transfers. Never prints secrets."""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path.home()
QBIT_CONF = HOME / ".config/qBittorrent/qBittorrent.conf"
NIC_DOWNLOADS = HOME / ".local/share/nicotine/downloads.json"
NIC_LIVE = HOME / ".cache/asus-panels/nicotine.json"
NIC_LIVE_MAX_AGE = 8.0

# 8080 is occupied by a *different* Docker qbittorrent-nox instance, so it is
# not used unless the desktop config itself points elsewhere later.
DEFAULT_PORTS = (8180, 8090, 8083)
KNOWN_BUSY = {8080, 8081, 8082}  # docker qbit, other stacks, phpMyAdmin

SECRET_KEY = re.compile(r"(password|passwd|hash|ha1|token|secret|apikey|api_key|cookie|key)", re.I)


def read_ini_section(path: Path, section: str) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    cur = None
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            continue
        if cur != section or "=" not in line:
            continue
        k, v = line.split("=", 1)
        data[k.strip()] = v
    return data


def qbit_api_key() -> str | None:
    web = read_ini_section(QBIT_CONF, "WebUI")
    for k, v in web.items():
        short = k.split("\\")[-1].lower().replace("_", "")
        if short in {"apikey"} or k.lower().endswith("apikey"):
            v = v.strip()
            return v or None
    return None


def qbit_configured_port() -> int | None:
    web = read_ini_section(QBIT_CONF, "WebUI")
    raw = web.get("Port") or web.get("WebUI\\Port")
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def qbit_enabled() -> bool:
    web = read_ini_section(QBIT_CONF, "WebUI")
    val = (web.get("Enabled") or web.get("WebUI\\Enabled") or "").strip().lower()
    return val in {"true", "1", "yes"}


def try_qbit(port: int, key: str | None) -> dict | None:
    url = f"http://127.0.0.1:{port}/api/v2/torrents/info"
    headers = {"User-Agent": "asus-panels/1.0"}
    if key:
        headers["X-Api-Key"] = key
        headers["X-API-Key"] = key
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=1.2) as resp:
            body = resp.read()
            data = json.loads(body.decode("utf-8", "replace"))
            if isinstance(data, list):
                return {"port": port, "torrents": data}
    except urllib.error.HTTPError as e:
        # 403 = server reached but auth failed / wrong instance
        return {"port": port, "http_error": e.code, "torrents": None}
    except Exception:
        return None
    return None


def fmt_eta(seconds: int) -> str:
    if seconds is None or seconds < 0 or seconds > 86400 * 30:
        return "—"
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)
    d, h = divmod(h, 24)
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {m:02d}m"
    return f"{m}m {s:02d}s"


def fmt_bytes(n: float | int | None) -> str:
    if n is None:
        return "—"
    n = float(n)
    units = ["B", "KB", "MB", "GB", "TB"]
    i = 0
    while n >= 1024 and i < len(units) - 1:
        n /= 1024
        i += 1
    if i == 0:
        return f"{int(n)} B"
    return f"{n:.1f} {units[i]}"


def fmt_speed(n: float | int | None) -> str:
    if not n or n <= 0:
        return "0 B/s"
    return fmt_bytes(n) + "/s"


ACTIVE_DL = {
    "downloading", "forcedDL", "metaDL", "forcedMetaDL",
    "stalledDL", "queuedDL", "checkingDL", "allocating",
    "pausedDL", "stoppedDL",
}


def normalize_qbit_items(torrents: list) -> tuple[list[dict], dict]:
    items = []
    up = 0
    down = 0
    for t in torrents:
        state = t.get("state") or ""
        progress = float(t.get("progress") or 0)
        dlspeed = int(t.get("dlspeed") or 0)
        upspeed = int(t.get("upspeed") or 0)
        down += dlspeed
        up += upspeed
        # active = downloading / queued / paused incomplete; skip finished seeds
        is_active = state in ACTIVE_DL or (progress < 1 and dlspeed > 0)
        if not is_active and progress >= 1:
            continue
        if not is_active and state in {"uploading", "forcedUP", "stalledUP", "queuedUP", "pausedUP", "stoppedUP", "checkingUP", "checkingResumeData", "moving", "unknown", "error"}:
            # keep stalled/paused incomplete only
            if progress >= 1:
                continue
        amount_left = t.get("amount_left")
        if amount_left is None:
            total = t.get("size") or t.get("total_size") or 0
            amount_left = max(0, int(total) - int(t.get("downloaded") or progress * total))
        items.append({
            "source": "qbittorrent",
            "name": t.get("name") or "torrent",
            "progress": progress,
            "speed": dlspeed,
            "speed_text": fmt_speed(dlspeed),
            "eta": t.get("eta") if isinstance(t.get("eta"), int) else -1,
            "eta_text": fmt_eta(t.get("eta") if isinstance(t.get("eta"), int) else -1),
            "left": amount_left,
            "left_text": fmt_bytes(amount_left),
            "size": t.get("size") or t.get("total_size") or 0,
            "size_text": fmt_bytes(t.get("size") or t.get("total_size") or 0),
            "state": state,
        })
    items.sort(key=lambda x: (-x["speed"], x["name"].lower()))
    totals = {
        "count": len(items),
        "down_speed": down,
        "up_speed": up,
        "down_text": fmt_speed(down),
        "up_text": fmt_speed(up),
    }
    return items, totals


def fetch_qbittorrent() -> dict:
    enabled = qbit_enabled()
    cfg_port = qbit_configured_port()
    key = qbit_api_key()
    if not enabled:
        return {
            "ok": False,
            "reason": "webui_disabled",
            "message": "La WebUI de qBittorrent está desactivada.",
            "items": [],
            "totals": {"count": 0, "down_speed": 0, "up_speed": 0, "down_text": "0 B/s", "up_text": "0 B/s"},
        }

    ports: list[int] = []
    if cfg_port and cfg_port not in KNOWN_BUSY:
        ports.append(cfg_port)
    for p in DEFAULT_PORTS:
        if p not in ports and p not in KNOWN_BUSY:
            ports.append(p)

    auth_seen = False
    last_err = None
    for port in ports:
        result = try_qbit(port, key)
        if not result:
            continue
        if result.get("torrents") is not None:
            items, totals = normalize_qbit_items(result["torrents"])
            return {
                "ok": True,
                "reason": "ok",
                "message": "",
                "port": port,
                "items": items,
                "totals": totals,
            }
        last_err = result.get("http_error")
        if last_err in {401, 403}:
            auth_seen = True

    if auth_seen:
        msg = "La WebUI responde pero pide autenticación. Revisa que la API key del conf siga válida."
        reason = "webui_auth"
    else:
        msg = (
            "No pude hablar con la WebUI de qBittorrent en localhost "
            f"(probé {', '.join(str(p) for p in ports) or 'ningún puerto'})."
        )
        reason = "webui_unreachable"
    return {
        "ok": False,
        "reason": reason,
        "message": msg,
        "auth_failed": auth_seen,
        "http_error": last_err,
        "items": [],
        "totals": {"count": 0, "down_speed": 0, "up_speed": 0, "down_text": "0 B/s", "up_text": "0 B/s"},
    }


def nicotine_running() -> bool:
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            comm = Path(f"/proc/{pid}/comm").read_text().strip().lower()
        except OSError:
            continue
        if comm in {"nicotine", "nicotine+", "pynicotine"}:
            return True
        try:
            argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\x00")
        except OSError:
            continue
        parts = [a.decode("utf-8", "replace") for a in argv if a]
        if not parts:
            continue
        base = Path(parts[0]).name.lower()
        if base in {"nicotine", "nicotine+", "pynicotine"}:
            return True
        # python -m pynicotine / python .../nicotine
        joined = " ".join(parts)
        if base.startswith("python") and ("/nicotine" in joined or "pynicotine" in joined):
            return True
    return False


def nic_basename(virtual_path: str) -> str:
    if not virtual_path:
        return "(archivo)"
    parts = re.split(r"[\\/]", virtual_path)
    return parts[-1] or virtual_path


ACTIVE_NIC = {
    "transferring", "queued", "paused", "getting status",
    "connection closed", "connection timeout", "user logged off",
    "download folder error", "local file error",
}


def _nic_item(name, user, progress, speed, eta, left, size, state):
    return {
        "source": "nicotine",
        "name": name,
        "user": user,
        "progress": progress,
        "speed": speed,
        "speed_text": fmt_speed(speed) if speed and speed > 0 else ("0 B/s" if speed == 0 and state.lower() == "transferring" else "—"),
        "eta": eta if isinstance(eta, int) else -1,
        "eta_text": fmt_eta(eta if isinstance(eta, int) else -1),
        "left": left,
        "left_text": fmt_bytes(left),
        "size": size,
        "size_text": fmt_bytes(size),
        "state": state,
    }


def fetch_nicotine_live() -> dict | None:
    """Prefer the asus_panels plugin snapshot if it is fresh."""
    if not NIC_LIVE.exists():
        return None
    try:
        age = time.time() - NIC_LIVE.stat().st_mtime
    except OSError:
        return None
    if age > NIC_LIVE_MAX_AGE:
        return None
    try:
        data = json.loads(NIC_LIVE.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    items = []
    down = 0
    for it in data.get("items") or []:
        if not isinstance(it, dict):
            continue
        speed = int(it.get("speed") or 0)
        down += max(speed, 0)
        size_n = int(it.get("size") or 0)
        left = int(it.get("left") if it.get("left") is not None else max(0, size_n))
        eta = it.get("eta")
        if not isinstance(eta, int):
            eta = -1
        items.append(_nic_item(
            it.get("name") or nic_basename(str(it.get("virtual_path") or "")),
            str(it.get("user") or ""),
            float(it.get("progress") or 0),
            speed,
            eta,
            left,
            size_n,
            str(it.get("state") or ""),
        ))
    return {
        "ok": True,
        "running": True,
        "live": True,
        "reason": "ok" if items else "no_active",
        "message": "" if items else "Sin descargas activas en Nicotine+.",
        "items": items,
        "totals": {"count": len(items), "down_speed": down, "down_text": fmt_speed(down)},
    }


def fetch_nicotine() -> dict:
    live = fetch_nicotine_live()
    if live is not None:
        return live
    running = nicotine_running()
    items: list[dict] = []
    if NIC_DOWNLOADS.exists() and NIC_DOWNLOADS.stat().st_size > 2:
        try:
            data = json.loads(NIC_DOWNLOADS.read_text(encoding="utf-8"))
        except Exception:
            data = []
        if isinstance(data, list):
            for row in data:
                if not isinstance(row, list) or len(row) < 5:
                    continue
                username, virtual, folder, status, size = row[0], row[1], row[2], row[3], row[4]
                offset = row[5] if len(row) > 5 else None
                status_s = str(status or "")
                st_l = status_s.lower()
                if st_l in {"finished", "cancelled", "filtered"}:
                    continue
                size_n = int(size or 0)
                off_n = int(offset or 0) if offset is not None else 0
                progress = (off_n / size_n) if size_n > 0 else 0.0
                left = max(0, size_n - off_n)
                items.append({
                    "source": "nicotine",
                    "name": nic_basename(str(virtual or "")),
                    "user": str(username or ""),
                    "progress": progress,
                    "speed": 0,
                    "speed_text": "—",
                    "eta": -1,
                    "eta_text": "—",
                    "left": left,
                    "left_text": fmt_bytes(left),
                    "size": size_n,
                    "size_text": fmt_bytes(size_n),
                    "state": status_s,
                })
    live = False  # downloads.json has no rate; written at most every 3 minutes
    if not running and not items:
        return {
            "ok": False,
            "running": False,
            "live": False,
            "reason": "not_running",
            "message": "Nicotine+ no está en ejecución.",
            "items": [],
            "totals": {"count": 0},
        }
    if running and not items:
        return {
            "ok": True,
            "running": True,
            "live": False,
            "reason": "no_active",
            "message": "Sin descargas activas en Nicotine+.",
            "items": [],
            "totals": {"count": 0},
        }
    msg = ""
    if items and not live:
        msg = "Progreso según el último guardado de Nicotine+ (cada 3 min). La velocidad en vivo requiere un plugin."
    return {
        "ok": True,
        "running": running,
        "live": live,
        "reason": "ok" if items else "no_active",
        "message": msg,
        "items": items,
        "totals": {"count": len(items)},
    }


def snapshot() -> dict:
    return {
        "ts": int(time.time()),
        "qbittorrent": fetch_qbittorrent(),
        "nicotine": fetch_nicotine(),
    }


def main() -> int:
    print(json.dumps(snapshot(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
