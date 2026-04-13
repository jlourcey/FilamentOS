# FilamentOS

**A complete filament management ecosystem for Creality and Flashforge 3D printer farms.**

FilamentOS connects your printers, CFS (Creality Filament System) boxes, and Spoolman filament database into a unified live dashboard — and lets you tag physical spool rings with NFC stickers so your phone can identify, assign, and track any spool in seconds.

![FilamentOS Dashboard](docs/dashboard-preview.png)

---

## What's Included

| Component | Description |
|---|---|
| **Spoolman** | Filament inventory database (web UI + API) |
| **Creality CFS Bridges** | Live telemetry from your CFS boxes via Moonraker |
| **FilamentOS Dashboard** | Dark-themed live monitoring dashboard |
| **CFS Sync Service** | Automatically updates spool usage from your printers |
| **SpoolmanNFC App** | Android app to write NFC tags and assign spools to slots |

---

## Credits

This project stands on the shoulders of excellent open-source work:

- **[Spoolman](https://github.com/Donkie/Spoolman)** by [@Donkie](https://github.com/Donkie) — the filament inventory database at the heart of everything
- **[Filament-Management (CFS Bridge)](https://github.com/jkef80/Filament-Management)** by [@jkef80](https://github.com/jkef80) — the bridge that translates Creality CFS telemetry into a usable API

FilamentOS adds the sync service, dashboard, and NFC app on top of these projects.

---

## Requirements

| Requirement | Details |
|---|---|
| **Windows PC** | Running Docker Desktop, always-on (your print server) |
| **Docker Desktop** | [Download here](https://www.docker.com/products/docker-desktop/) |
| **PowerShell 5+** | Built into Windows — just search "PowerShell" in Start |
| **Android phone** | With NFC support, for the SpoolmanNFC app |
| **NFC tags** | Mifare Classic 1K sticker tags (cheap on Amazon) |
| **Creality printers** | K1C, K2 Pro, or similar with CFS boxes and Moonraker/Fluidd |

> **Flashforge printers** (AD5M, etc.) are supported in display-only mode — they connect directly to Spoolman via their own integration.

---

## Quick Start

### Step 1 — Download this repository

Click the green **Code** button above → **Download ZIP** → extract to a folder like `C:\FilamentOS`

### Step 2 — Run the setup script

Open **PowerShell** (search "PowerShell" in Start menu) and run:

```powershell
cd C:\FilamentOS
.\setup.ps1
```

The script will ask you step by step for:
- Your PC's local IP address
- How many printers you have
- Each printer's name, IP, type, and CFS configuration

It then generates all config files and deploys everything automatically.

### Step 3 — Register custom fields in Spoolman

Open Spoolman at `http://YOUR-PC-IP:7912`, go to **Settings → Custom Fields** and add these four fields for **Spool**:

| Field Key | Type | Description |
|---|---|---|
| `cfs_rfid` | Text | NFC tag UID linked to this spool |
| `cfs_slot` | Text | CFS slot assignment (e.g. 2A) |
| `cfs_printer` | Text | Printer IP this spool is assigned to |
| `cfs_last_seen` | Text | Last sync timestamp |

### Step 4 — Install the SpoolmanNFC Android app

Download `SpoolmanNFC.apk` from the [Releases page](../../releases) and install it on your Android phone.

When you first open the app, go to **Settings** and enter:
- Your Spoolman URL: `http://YOUR-PC-IP:7912`

### Step 5 — Tag your spools

1. Open SpoolmanNFC on your phone
2. Tap a spool from your inventory
3. Select which printer and slot it lives in
4. Tap **Write & Link Tag**
5. Hold your phone over the NFC sticker on the spool ring

Done — that spool is now tracked. The sync service will automatically update its used weight as you print.

---

## Accessing Your System

| Service | URL | Description |
|---|---|---|
| Spoolman | `http://YOUR-PC-IP:7912` | Full inventory management |
| FilamentOS Dashboard | `http://YOUR-PC-IP:7914` | Live monitoring dashboard |
| K1C Bridge UI | `http://YOUR-PC-IP:8001` | Raw CFS telemetry (K1C) |
| K2Pro Bridge UI | `http://YOUR-PC-IP:8002` | Raw CFS telemetry (K2Pro) |

---

## How Slot Naming Works

CFS boxes use a letter+number system. Each box has 4 slots (A, B, C, D). The box number depends on which slot your CFS is physically plugged into on the printer.

**Example:** A K1C with one CFS plugged into Box 2 has slots: `2A`, `2B`, `2C`, `2D`

**Example:** A K2 Pro with two CFS boxes has slots: `1A`, `1B`, `1C`, `1D`, `2A`, `2B`, `2C`, `2D`

The setup script will ask you which box number each CFS is in.

---

## Updating

To pull the latest version:

```powershell
cd C:\FilamentOS
git pull
docker compose up -d --build
```

---

## Troubleshooting

**Dashboard shows no data**
- Make sure all containers are running: `docker ps`
- Check that your browser can reach `http://YOUR-PC-IP:7912`

**Sync service not updating weights**
- Make sure spools are assigned to slots using the NFC app
- Check sync logs: `docker logs cfs_sync --tail 50`
- Verify your printer IP and Moonraker are reachable

**NFC app can't connect to Spoolman**
- Make sure your phone is on the same WiFi network as your PC
- Double-check the Spoolman URL in the app settings

**CFS bridge shows offline**
- Verify Moonraker is running on your printer (check Fluidd/Mainsail)
- Check bridge logs: `docker logs creality-bridge-k1c --tail 50`

---

## Project Structure

```
FilamentOS/
├── setup.ps1                    # Interactive setup script — start here
├── docker-compose.yml           # Generated by setup.ps1
├── .env                         # Generated by setup.ps1
├── spoolman_sync/
│   ├── sync.py                  # CFS → Spoolman sync service
│   ├── requirements.txt
│   └── Dockerfile
├── spoolman_dashboard/
│   ├── index.html               # FilamentOS dashboard
│   ├── nginx.conf               # Generated by setup.ps1
│   └── Dockerfile
└── docs/
    └── SETUP_GUIDE.md           # Detailed setup instructions
```

---

## License

MIT License — use freely, give credit where it's due.

Special thanks to [@Donkie](https://github.com/Donkie) and [@jkef80](https://github.com/jkef80) for their foundational work.
