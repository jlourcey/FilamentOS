#!/usr/bin/env python3
"""
==========================================================================
FilamentOS — CFS → Spoolman Sync Service
==========================================================================

Polls all configured Creality bridge APIs and syncs filament usage into
Spoolman automatically based on spool slot assignments.

HOW SPOOL MATCHING WORKS
  Spools are matched by slot assignment (cfs_slot + cfs_printer fields).
  When you tag a spool with the SpoolmanNFC app and assign it to a slot,
  this service finds that assignment and updates the used weight.

ENVIRONMENT VARIABLES
  SPOOLMAN_URL        URL to Spoolman (e.g. http://spoolman:7912)
  BRIDGE_1_URL        URL to first bridge  (e.g. http://192.168.1.100:8001)
  BRIDGE_1_NAME       Name of first printer (e.g. K1C)
  BRIDGE_1_IP         IP of first printer   (e.g. 192.168.1.50)
  BRIDGE_2_URL        URL to second bridge (optional)
  BRIDGE_2_NAME       Name of second printer (optional)
  BRIDGE_2_IP         IP of second printer (optional)
  ... up to BRIDGE_8
  POLL_INTERVAL       Seconds between polls (default: 30)
  LOG_LEVEL           INFO or DEBUG (default: INFO)

Credits:
  Spoolman by Donkie   — https://github.com/Donkie/Spoolman
  CFS Bridge by jkef80 — https://github.com/jkef80/Filament-Management
==========================================================================
"""

import os
import sys
import time
import json
import logging
import requests
from datetime import datetime, timezone

# ── Configuration ──────────────────────────────────────────────────────────
SPOOLMAN_URL  = os.environ.get("SPOOLMAN_URL", "http://spoolman:7912").rstrip("/")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "30"))
LOG_LEVEL     = os.environ.get("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("filamentos-sync")

# Build bridge list from environment variables (BRIDGE_1_*, BRIDGE_2_*, etc.)
BRIDGES = []
for i in range(1, 9):
    url  = os.environ.get(f"BRIDGE_{i}_URL", "").strip()
    name = os.environ.get(f"BRIDGE_{i}_NAME", f"Printer{i}").strip()
    ip   = os.environ.get(f"BRIDGE_{i}_IP", "").strip()
    if url and ip:
        BRIDGES.append({"name": name, "url": url, "ip": ip})

if not BRIDGES:
    log.warning("No bridges configured. Set BRIDGE_1_URL, BRIDGE_1_NAME, BRIDGE_1_IP etc.")


# =============================================================================
# Spoolman API helpers
# =============================================================================

def spoolman_get(path, params=None):
    try:
        r = requests.get(f"{SPOOLMAN_URL}{path}", params=params, timeout=10)
        r.raise_for_status()
        return r.json()
    except requests.exceptions.RequestException as e:
        log.warning(f"Spoolman GET {path} failed: {e}")
        return None


def spoolman_patch(path, payload):
    try:
        r = requests.patch(f"{SPOOLMAN_URL}{path}", json=payload, timeout=10)
        if r.status_code in (200, 204):
            return True
        log.warning(f"Spoolman PATCH {path} -> HTTP {r.status_code}: {r.text[:200]}")
        return False
    except requests.exceptions.RequestException as e:
        log.warning(f"Spoolman PATCH {path} failed: {e}")
        return False


def decode_extra(extra_dict):
    """
    Spoolman 0.23.1 stores extra values as JSON-encoded strings.
    e.g. {"cfs_slot": '"2D"'} -> {"cfs_slot": "2D"}
    """
    if not extra_dict:
        return {}
    result = {}
    for k, v in extra_dict.items():
        try:
            parsed = json.loads(v)
            result[k] = parsed if isinstance(parsed, str) else v
        except Exception:
            result[k] = v
    return result


def fetch_all_spools():
    """
    Returns a lookup dict: { (printer_ip, slot_id) -> spool_dict }
    """
    data = spoolman_get("/api/v1/spool")
    if not data:
        return {}

    by_slot = {}
    for spool in data:
        raw_extra = spool.get("extra") or {}
        extra = decode_extra(raw_extra)
        slot    = extra.get("cfs_slot", "").strip()
        printer = extra.get("cfs_printer", "").strip()
        if slot and printer:
            by_slot[(printer, slot)] = spool
            log.debug(f"  Spool {spool['id']} → {printer} slot {slot}")

    log.debug(f"Loaded {len(data)} spools — {len(by_slot)} slot-assigned")
    return by_slot


def update_spool_usage(spool_id, used_g):
    return spoolman_patch(f"/api/v1/spool/{spool_id}", {
        "used_weight": round(used_g, 2),
    })


# =============================================================================
# Bridge API helpers
# =============================================================================

def fetch_bridge_state(bridge):
    try:
        r = requests.get(f"{bridge['url']}/api/ui/state", timeout=10)
        r.raise_for_status()
        return r.json().get("result")
    except requests.exceptions.RequestException as e:
        log.debug(f"[{bridge['name']}] Bridge unreachable: {e}")
        return None


# =============================================================================
# Core sync logic
# =============================================================================

def sync_bridge(bridge, state, by_slot):
    matched = skipped = 0

    if not state.get("printer_connected"):
        log.info(f"[{bridge['name']}] Printer not connected — skipping.")
        return 0, 0

    if not state.get("cfs_connected"):
        log.info(f"[{bridge['name']}] CFS not connected — skipping.")
        return 0, 0

    cfs_slots = state.get("cfs_slots", {})
    slot_info = state.get("slots", {})

    for slot_id, slot_data in cfs_slots.items():
        if slot_id.startswith("_") or not slot_data.get("present"):
            continue

        consumed_g = 0.0
        if slot_id in slot_info:
            consumed_g = slot_info[slot_id].get("spool_consumed_g") or 0.0

        if consumed_g <= 0:
            continue

        spool = by_slot.get((bridge["ip"], slot_id))

        if spool:
            ok = update_spool_usage(spool["id"], consumed_g)
            if ok:
                matched += 1
                log.info(
                    f"[{bridge['name']}]   ✓ Slot {slot_id} → spool {spool['id']} "
                    f"used={consumed_g:.1f}g updated"
                )
            else:
                skipped += 1
        else:
            skipped += 1
            log.info(
                f"[{bridge['name']}]   ✗ Slot {slot_id} — no spool assigned. "
                f"Use SpoolmanNFC app to assign a spool to this slot."
            )

    return matched, skipped


# =============================================================================
# Startup health check
# =============================================================================

def wait_for_spoolman(max_attempts=20, delay=5):
    log.info(f"Waiting for Spoolman at {SPOOLMAN_URL} ...")
    for attempt in range(1, max_attempts + 1):
        try:
            r = requests.get(f"{SPOOLMAN_URL}/api/v1/info", timeout=5)
            if r.status_code == 200:
                version = r.json().get("version", "?")
                log.info(f"Spoolman v{version} ready.")
                return True
        except requests.exceptions.RequestException:
            pass
        log.info(f"  Not ready (attempt {attempt}/{max_attempts}), retrying in {delay}s...")
        time.sleep(delay)
    log.error("Spoolman never became ready. Exiting.")
    return False


# =============================================================================
# Main loop
# =============================================================================

def main():
    log.info("=" * 60)
    log.info("FilamentOS CFS → Spoolman Sync Service starting")
    log.info(f"  Spoolman     : {SPOOLMAN_URL}")
    log.info(f"  Poll interval: {POLL_INTERVAL}s")
    for b in BRIDGES:
        log.info(f"  Bridge       : {b['name']} @ {b['url']} (printer IP: {b['ip']})")
    if not BRIDGES:
        log.info("  Bridges      : none configured")
    log.info("=" * 60)

    if not wait_for_spoolman():
        sys.exit(1)

    while True:
        log.info("─" * 60)
        log.info(f"Sync cycle — {datetime.now(timezone.utc).strftime('%H:%M:%S UTC')}")

        by_slot = fetch_all_spools()
        log.info(f"  {len(by_slot)} spools with slot assignments")

        total_matched = total_skipped = 0

        for bridge in BRIDGES:
            state = fetch_bridge_state(bridge)
            if state is None:
                log.warning(f"[{bridge['name']}] No response from bridge")
                continue
            m, s = sync_bridge(bridge, state, by_slot)
            total_matched += m
            total_skipped += s

        log.info(f"Cycle complete — matched={total_matched} skipped={total_skipped}")
        log.info(f"Next sync in {POLL_INTERVAL}s ...")
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
