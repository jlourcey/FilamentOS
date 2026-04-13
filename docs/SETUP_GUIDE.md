# FilamentOS — Detailed Setup Guide

This guide walks through the complete setup in detail. If you just want to get running quickly, follow the README instead.

---

## Prerequisites

### 1. Install Docker Desktop

Docker Desktop runs all the FilamentOS services as containers — no manual software installation needed beyond Docker itself.

1. Go to https://www.docker.com/products/docker-desktop/
2. Download and install the Windows version
3. Open Docker Desktop and wait for it to say "Running" in the bottom left
4. Leave it running in the background — it starts automatically with Windows

### 2. Verify your printers have Moonraker

FilamentOS communicates with Creality printers via Moonraker, which is the API layer built into Fluidd/Mainsail.

- Open your printer's Fluidd or Mainsail interface in a browser
- If you can see it, Moonraker is running ✓
- Note down your printer's IP address (shown in the Fluidd/Mainsail URL)

### 3. Get your PC's local IP address

1. Open PowerShell and run: `ipconfig`
2. Look for "IPv4 Address" under your active network adapter
3. It will look like `192.168.x.x` — write this down

---

## Running the Setup Script

1. Download and extract FilamentOS to `C:\FilamentOS`
2. Open PowerShell (search "PowerShell" in Start menu — right-click → Run as Administrator if prompted)
3. Run:
   ```powershell
   cd C:\FilamentOS
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   .\setup.ps1
   ```
4. Answer each question as prompted

The script will:
- Ask for your PC's IP and printer details
- Generate all config files
- Pull Docker images and start all containers
- Print a summary with your access URLs

---

## Setting Up Spoolman Custom Fields

This step is required for the NFC app and sync service to work correctly.

1. Open Spoolman at `http://YOUR-PC-IP:7912`
2. Click the gear icon (Settings) in the top right
3. Go to **Custom Fields**
4. Add these four fields — make sure to select **Spool** as the resource type:

| Field Key | Type | What it stores |
|---|---|---|
| `cfs_rfid` | Text | The NFC tag UID linked to this spool |
| `cfs_slot` | Text | Which CFS slot this spool lives in (e.g. `2D`) |
| `cfs_printer` | Text | IP address of the printer this spool is assigned to |
| `cfs_last_seen` | Text | When this spool was last synced |

> **Important:** The field keys must be typed exactly as shown above, including lowercase and underscores.

---

## Adding Your Filament Inventory

Before tagging spools, add your filament to Spoolman:

1. Go to **Filaments** → **Add Filament**
2. Enter the vendor, material, color, and weight for each filament type you own
3. Go to **Spools** → **Add Spool**
4. Link each physical spool to its filament entry
5. Set an approximate remaining weight if known

---

## Installing the SpoolmanNFC Android App

1. Download `SpoolmanNFC.apk` from the [Releases page](../../releases)
2. On your Android phone, go to **Settings → Security** and enable **Install unknown apps** for your browser or Files app
3. Transfer the APK to your phone (email it to yourself, or use a USB cable)
4. Open the APK file and tap Install
5. Open the SpoolmanNFC app
6. When prompted, enter your Spoolman URL: `http://YOUR-PC-IP:7912`

> **Note:** Your phone must be on the same WiFi network as your PC for the app to connect.

---

## Tagging Your Spool Rings

You'll need Mifare Classic 1K NFC sticker tags. These are widely available on Amazon for a few dollars per pack.

1. Stick an NFC tag on each spool ring
2. Open SpoolmanNFC on your phone
3. Your spool inventory will load automatically
4. Tap any spool you want to tag
5. Select which printer it belongs to
6. Select which CFS slot it's loaded into
7. Tap **Write & Link Tag**
8. Hold your phone flat over the NFC sticker on the spool

The app writes the spool information to the tag and links the tag's unique ID to that spool in Spoolman. From that point on, the sync service automatically tracks usage.

---

## Verifying Everything Works

### Check containers are running:
```powershell
docker ps
```
All containers should show `Up` status.

### Check the sync service is matching spools:
```powershell
docker logs cfs_sync --tail 20
```
You should see lines like:
```
✓ Slot 2D → spool 47 (PETG) used=101.2g updated
```

### Check the dashboard:
Open `http://YOUR-PC-IP:7914` in your browser. You should see:
- Your printers with live CFS slot status
- Color swatches for loaded filament
- Spool inventory with remaining weight

---

## CFS Slot Naming

Understanding how CFS slots are named helps when assigning spools:

- Each CFS box has 4 slots labeled A, B, C, D
- The box number depends on which port it's plugged into on the printer
- Example: One CFS in Box 2 → slots are `2A`, `2B`, `2C`, `2D`
- Example: Two CFS boxes in Box 1 and Box 2 → slots are `1A`-`1D` and `2A`-`2D`

Check your printer's physical CFS port labels to determine box numbers.

---

## Keeping FilamentOS Updated

```powershell
cd C:\FilamentOS
git pull
docker compose up -d --build
```

---

## Common Issues

**"Cannot connect to Docker daemon"**
→ Docker Desktop isn't running. Open it from the Start menu.

**Dashboard loads but shows no data**
→ Open browser developer tools (F12), check the Console tab for errors.
→ Make sure all containers are running: `docker ps`

**Sync service shows "no spool assigned"**
→ Use the SpoolmanNFC app to assign the spool to a slot first.
→ Make sure you registered the custom fields in Spoolman settings.

**NFC app can't connect to Spoolman**
→ Check your phone is on the same WiFi as your PC.
→ Verify the Spoolman URL includes `http://` and the correct port.

**Bridge shows offline in dashboard**
→ Verify your printer's Moonraker is accessible: open Fluidd/Mainsail in a browser.
→ Check the printer IP matches what you entered during setup.

---

## Getting Help

- Open an issue on GitHub
- Check the logs: `docker logs <container-name> --tail 50`
