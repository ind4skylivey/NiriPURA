# Write live download stats for the ASUS Quickshell panel.
# Output: ~/.cache/asus-panels/nicotine.json  (every 2 seconds)

import json
import os
import re
import time
from pathlib import Path

from pynicotine.events import events
from pynicotine.pluginsystem import BasePlugin
from pynicotine.transfers import TransferStatus

OUT_PATH = Path.home() / ".cache" / "asus-panels" / "nicotine.json"
SKIP_STATUS = {
    TransferStatus.FINISHED,
    TransferStatus.CANCELLED,
    TransferStatus.FILTERED,
}


def _basename(virtual_path):
    if not virtual_path:
        return "(archivo)"
    return re.split(r"[\\/]", str(virtual_path))[-1] or str(virtual_path)


class Plugin(BasePlugin):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._timer_id = None

    def init(self):
        OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._timer_id = events.schedule(delay=2, callback=self._dump, repeat=True)
        self._dump()

    def disable(self):
        if self._timer_id is not None:
            events.cancel_scheduled(self._timer_id)
            self._timer_id = None

    def unloaded_notification(self):
        self.disable()

    def shutdown_notification(self):
        self.disable()

    def _dump(self):
        items = []
        total_speed = 0
        try:
            transfers = self.core.downloads.transfers
        except Exception:
            transfers = {}

        for transfer in list(transfers.values()):
            status = getattr(transfer, "status", None) or ""
            if status in SKIP_STATUS:
                continue
            size = int(getattr(transfer, "size", 0) or 0)
            offset = getattr(transfer, "current_byte_offset", None)
            offset_n = int(offset or 0)
            progress = (offset_n / size) if size > 0 else 0.0
            speed = int(getattr(transfer, "speed", 0) or 0)
            total_speed += max(speed, 0)
            eta = getattr(transfer, "time_left", None)
            if eta is None:
                eta = -1
            else:
                try:
                    eta = int(eta)
                except (TypeError, ValueError):
                    eta = -1
            left = max(0, size - offset_n)
            items.append({
                "name": _basename(getattr(transfer, "virtual_path", "")),
                "user": getattr(transfer, "username", "") or "",
                "progress": progress,
                "speed": speed,
                "eta": eta,
                "left": left,
                "size": size,
                "state": str(status),
            })

        payload = {
            "ts": int(time.time()),
            "running": True,
            "live": True,
            "items": items,
            "totals": {"count": len(items), "down_speed": total_speed},
        }
        tmp = OUT_PATH.with_suffix(".json.tmp")
        try:
            tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, OUT_PATH)
        except OSError:
            try:
                if tmp.exists():
                    tmp.unlink()
            except OSError:
                pass
