# =============================================================================
# FilamentOS Setup Script
# =============================================================================
# This script sets up the complete FilamentOS filament management system.
# Run it from PowerShell in the FilamentOS folder.
#
# What it does:
#   1. Asks for your network and printer information
#   2. Generates all configuration files
#   3. Deploys all Docker containers automatically
# =============================================================================

$ErrorActionPreference = "Stop"

# ── Banner ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ███████╗██╗██╗      █████╗ ███╗   ███╗███████╗███╗   ██╗████████╗ ██████╗ ███████╗" -ForegroundColor Red
Write-Host "  ██╔════╝██║██║     ██╔══██╗████╗ ████║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔════╝" -ForegroundColor Red
Write-Host "  █████╗  ██║██║     ███████║██╔████╔██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║███████╗" -ForegroundColor DarkRed
Write-Host "  ██╔══╝  ██║██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║   ██║   ██║╚════██║" -ForegroundColor DarkRed
Write-Host "  ██║     ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗██║ ╚████║   ██║   ╚██████╔╝███████║" -ForegroundColor DarkRed
Write-Host "  ╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚══════╝" -ForegroundColor DarkRed
Write-Host ""
Write-Host "  Print Farm Filament Management System" -ForegroundColor Gray
Write-Host "  Powered by Spoolman (Donkie) + CFS Bridge (jkef80)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Helper functions ──────────────────────────────────────────────────────────
function Ask($prompt, $default = "") {
    if ($default) {
        $input = Read-Host "$prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($input)) { return $default }
        return $input.Trim()
    }
    do {
        $input = Read-Host $prompt
    } while ([string]::IsNullOrWhiteSpace($input))
    return $input.Trim()
}

function AskYesNo($prompt) {
    do {
        $input = Read-Host "$prompt (y/n)"
    } while ($input -notmatch '^[yYnN]$')
    return $input -match '^[yY]$'
}

function AskInt($prompt, $min, $max) {
    do {
        $input = Read-Host $prompt
        $n = 0
        $valid = [int]::TryParse($input, [ref]$n) -and $n -ge $min -and $n -le $max
        if (-not $valid) { Write-Host "  Please enter a number between $min and $max" -ForegroundColor Yellow }
    } while (-not $valid)
    return $n
}

function Step($n, $title) {
    Write-Host ""
    Write-Host "  STEP $n — $title" -ForegroundColor Red
    Write-Host "  $("─" * ($title.Length + 9))" -ForegroundColor DarkGray
    Write-Host ""
}

function Info($msg)    { Write-Host "  ℹ  $msg" -ForegroundColor Cyan }
function Success($msg) { Write-Host "  ✓  $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "  ⚠  $msg" -ForegroundColor Yellow }

# ── Check Docker ──────────────────────────────────────────────────────────────
Step 1 "Checking Prerequisites"

try {
    $dockerVersion = docker --version 2>&1
    Success "Docker found: $dockerVersion"
} catch {
    Write-Host ""
    Write-Host "  ERROR: Docker is not installed or not running." -ForegroundColor Red
    Write-Host "  Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

try {
    docker ps 2>&1 | Out-Null
    Success "Docker is running"
} catch {
    Write-Host ""
    Write-Host "  ERROR: Docker Desktop is not running. Please start it and try again." -ForegroundColor Red
    exit 1
}

# ── Network configuration ─────────────────────────────────────────────────────
Step 2 "Network Configuration"

Info "Your PC's local IP address is what other devices use to reach this server."
Info "It usually looks like 192.168.x.x or 10.0.x.x"
Write-Host ""

# Try to auto-detect local IP
$detectedIP = ""
try {
    $detectedIP = (Get-NetIPAddress -AddressFamily IPv4 | 
        Where-Object { $_.InterfaceAlias -notmatch "Loopback|Virtual|vEthernet" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -First 1).IPAddress
} catch {}

$HOST_IP = Ask "Enter your PC's local IP address" $detectedIP
Success "Host IP set to: $HOST_IP"

# ── Printer configuration ─────────────────────────────────────────────────────
Step 3 "Printer Configuration"

Info "Now let's set up your printers. FilamentOS supports:"
Write-Host "    • Creality K1C, K2 Pro, and similar (with CFS boxes)" -ForegroundColor Gray
Write-Host "    • Flashforge AD5M and similar (direct connection, display only)" -ForegroundColor Gray
Write-Host ""

$printerCount = AskInt "How many printers do you have?" 1 10
Write-Host ""

$printers = @()
$bridgePort = 8001

for ($i = 1; $i -le $printerCount; $i++) {
    Write-Host "  ── Printer $i of $printerCount ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    $printerName = Ask "  Printer $i name (e.g. K1C, K2Pro, AD5M)"
    $printerIP   = Ask "  Printer $i IP address (e.g. 192.168.1.100)"
    
    Write-Host ""
    Write-Host "  Printer type:" -ForegroundColor Gray
    Write-Host "    1) Creality with CFS (K1C, K2 Pro, etc.)" -ForegroundColor Gray
    Write-Host "    2) Flashforge / other (display only, no CFS)" -ForegroundColor Gray
    Write-Host ""
    $typeChoice = AskInt "  Select type (1 or 2)" 1 2
    
    if ($typeChoice -eq 1) {
        # Creality with CFS
        $cfsCount = AskInt "  How many CFS boxes are connected to this printer?" 1 4
        
        $cfsBoxes = @()
        for ($c = 1; $c -le $cfsCount; $c++) {
            Write-Host ""
            Info "CFS Box $c — which box number is it physically plugged into on the printer?"
            Info "Check your printer's CFS port labels. Usually Box 1 or Box 2."
            $boxNum = AskInt "  Box number for CFS $c" 1 4
            $cfsBoxes += $boxNum
        }
        
        # Build slot labels from box numbers
        $slotLabels = @()
        foreach ($box in $cfsBoxes) {
            foreach ($slot in @("A","B","C","D")) {
                $slotLabels += "${box}${slot}"
            }
        }
        
        $printer = @{
            Name       = $printerName
            IP         = $printerIP
            Type       = "creality_cfs"
            BridgePort = $bridgePort
            CfsBoxes   = $cfsBoxes
            SlotLabels = $slotLabels
        }
        $bridgePort++
    } else {
        # Flashforge / direct connect
        $printer = @{
            Name       = $printerName
            IP         = $printerIP
            Type       = "direct"
            BridgePort = 0
            CfsBoxes   = @()
            SlotLabels = @("E1")
        }
    }
    
    $printers += $printer
    Write-Host ""
    Success "Printer '$printerName' configured"
    Write-Host ""
}

# ── Port configuration ────────────────────────────────────────────────────────
Step 4 "Service Ports"

Info "FilamentOS uses these ports by default. Change them if they conflict with other services."
Write-Host ""

$PORT_SPOOLMAN  = Ask "Spoolman port" "7912"
$PORT_EXTENSION = Ask "Extension API port" "7913"
$PORT_DASHBOARD = Ask "Dashboard port" "7914"

Write-Host ""
Success "Ports configured"

# ── Generate .env file ────────────────────────────────────────────────────────
Step 5 "Generating Configuration Files"

$envContent = @"
# FilamentOS Environment Configuration
# Generated by setup.ps1 on $(Get-Date -Format "yyyy-MM-dd HH:mm")
# Edit this file to change settings, then run: docker compose up -d

HOST_IP=$HOST_IP
PORT_SPOOLMAN=$PORT_SPOOLMAN
PORT_EXTENSION=$PORT_EXTENSION
PORT_DASHBOARD=$PORT_DASHBOARD
POLL_INTERVAL=30
LOG_LEVEL=INFO
"@

Set-Content -Path ".env" -Value $envContent
Success "Generated .env"

# ── Generate docker-compose.yml ───────────────────────────────────────────────
$composeServices = @"
services:

  # ── Spoolman — Filament Database ──────────────────────────────────────────
  # Credit: https://github.com/Donkie/Spoolman
  spoolman:
    image: ghcr.io/donkie/spoolman:latest
    container_name: spoolman
    restart: unless-stopped
    ports:
      - "${PORT_SPOOLMAN}:7912"
    volumes:
      - spoolman_data:/home/app/.local/share/spoolman
    environment:
      - SPOOLMAN_PORT=7912
    healthcheck:
      test: ["CMD-SHELL", "true"]
      interval: 10s
      timeout: 5s
      retries: 1

  # ── CFS → Spoolman Sync Service ───────────────────────────────────────────
  cfs_sync:
    build:
      context: ./spoolman_sync
      dockerfile: Dockerfile
    container_name: cfs_sync
    restart: unless-stopped
    depends_on:
      spoolman:
        condition: service_healthy
    environment:
      - SPOOLMAN_URL=http://spoolman:7912
      - POLL_INTERVAL=${POLL_INTERVAL}
      - LOG_LEVEL=${LOG_LEVEL}
"@

# Add bridge URLs to sync service
$bridgeIdx = 1
foreach ($printer in $printers) {
    if ($printer.Type -eq "creality_cfs") {
        $composeServices += "`n      - BRIDGE_${bridgeIdx}_URL=http://${HOST_IP}:$($printer.BridgePort)"
        $composeServices += "`n      - BRIDGE_${bridgeIdx}_NAME=$($printer.Name)"
        $composeServices += "`n      - BRIDGE_${bridgeIdx}_IP=$($printer.IP)"
        $bridgeIdx++
    }
}

$composeServices += @"

    extra_hosts:
      - "host.docker.internal:host-gateway"

  # ── FilamentOS Dashboard ──────────────────────────────────────────────────
  dashboard:
    build:
      context: ./spoolman_dashboard
      dockerfile: Dockerfile
    container_name: filament_dashboard
    restart: unless-stopped
    ports:
      - "${PORT_DASHBOARD}:80"

"@

# Add Creality bridges
foreach ($printer in $printers) {
    if ($printer.Type -eq "creality_cfs") {
        $bridgeName = $printer.Name.ToLower() -replace '[^a-z0-9]', '-'
        $composeServices += @"

  # ── CFS Bridge: $($printer.Name) ─────────────────────────────────────────
  # Credit: https://github.com/jkef80/Filament-Management
  creality-bridge-$bridgeName:
    image: ghcr.io/jkef80/filament-management:latest
    container_name: creality-bridge-$bridgeName
    restart: unless-stopped
    ports:
      - "$($printer.BridgePort):8000"
    volumes:
      - ./bridges/$bridgeName:/app/data
    environment:
      - MOONRAKER_URL=http://$($printer.IP):7125
      - SPOOLMAN_URL=http://${HOST_IP}:${PORT_SPOOLMAN}
      - PRINTER_IP=$($printer.IP)

"@
    }
}

$composeServices += @"

volumes:
  spoolman_data:
    driver: local
"@

Set-Content -Path "docker-compose.yml" -Value $composeServices
Success "Generated docker-compose.yml"

# ── Generate bridge config folders ───────────────────────────────────────────
foreach ($printer in $printers) {
    if ($printer.Type -eq "creality_cfs") {
        $bridgeName = $printer.Name.ToLower() -replace '[^a-z0-9]', '-'
        New-Item -ItemType Directory -Path "bridges\$bridgeName" -Force | Out-Null
        
        $bridgeConfig = @"
{
  "moonraker_url": "http://$($printer.IP):7125",
  "spoolman_url": "http://${HOST_IP}:${PORT_SPOOLMAN}",
  "printer_ip": "$($printer.IP)",
  "bridge_port": 8000
}
"@
        Set-Content -Path "bridges\$bridgeName\config.json" -Value $bridgeConfig
        Success "Generated bridge config for $($printer.Name)"
    }
}

# ── Generate dashboard nginx.conf ─────────────────────────────────────────────
$nginxConf = @"
server {
    listen 80;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    location /proxy/spoolman/ {
        proxy_pass http://${HOST_IP}:${PORT_SPOOLMAN}/;
        proxy_set_header Host ${HOST_IP};
    }
"@

$bIdx = 1
foreach ($printer in $printers) {
    if ($printer.Type -eq "creality_cfs") {
        $nginxConf += @"

    location /proxy/bridge${bIdx}/ {
        proxy_pass http://${HOST_IP}:$($printer.BridgePort)/;
        proxy_set_header Host ${HOST_IP};
    }
"@
        $bIdx++
    }
}

$nginxConf += @"

}
"@

Set-Content -Path "spoolman_dashboard\nginx.conf" -Value $nginxConf
Success "Generated nginx.conf"

# ── Generate dashboard index.html ─────────────────────────────────────────────
# Build the PRINTERS JS array
$printersJS = "const PRINTERS = [`n"
$bIdx = 1
foreach ($printer in $printers) {
    $slots = $printer.SlotLabels | ForEach-Object { "'$_'" }
    $slotsStr = $slots -join ","
    
    if ($printer.Type -eq "creality_cfs") {
        # Build boxes array
        $boxesJS = "["
        foreach ($box in $printer.CfsBoxes) {
            $boxSlots = $printer.SlotLabels | Where-Object { $_ -match "^${box}" }
            $boxSlotsStr = ($boxSlots | ForEach-Object { "'$_'" }) -join ","
            $boxesJS += "{ id: $box, slots: [$boxSlotsStr] },"
        }
        $boxesJS += "]"
        
        $printersJS += "  { name: '$($printer.Name)', ip: '$($printer.IP)', bridgeUrl: '/proxy/bridge${bIdx}', slots: [$slotsStr], boxes: $boxesJS },`n"
        $bIdx++
    } else {
        $printersJS += "  { name: '$($printer.Name)', ip: '$($printer.IP)', bridgeUrl: null, slots: ['E1'], boxes: [{ id: 1, slots: ['E1'] }] },`n"
    }
}
$printersJS += "];"

# Read the template dashboard and inject the PRINTERS config
$dashboardTemplate = Get-Content "spoolman_dashboard\index.html" -Raw

# Replace the PRINTERS block
$dashboardTemplate = $dashboardTemplate -replace "const PRINTERS = \[[\s\S]*?\];", $printersJS

# Replace API URLs to use proxy
$dashboardTemplate = $dashboardTemplate -replace "const SPOOLMAN\s+=\s+'http://[^']*'", "const SPOOLMAN = '/proxy/spoolman'"

Set-Content -Path "spoolman_dashboard\index.html" -Value $dashboardTemplate
Success "Generated dashboard configuration"

# ── Deploy ────────────────────────────────────────────────────────────────────
Step 6 "Deploying FilamentOS"

Info "Building and starting all containers. This may take a few minutes on first run..."
Write-Host ""

docker compose up -d --build 2>&1 | ForEach-Object {
    Write-Host "  $_" -ForegroundColor DarkGray
}

Write-Host ""

# Check status
$running = docker ps --format "{{.Names}}" 2>&1
$failed = @()

$expectedContainers = @("spoolman", "cfs_sync", "filament_dashboard")
foreach ($printer in $printers) {
    if ($printer.Type -eq "creality_cfs") {
        $bridgeName = $printer.Name.ToLower() -replace '[^a-z0-9]', '-'
        $expectedContainers += "creality-bridge-$bridgeName"
    }
}

foreach ($container in $expectedContainers) {
    if ($running -match $container) {
        Success "Container '$container' is running"
    } else {
        Warn "Container '$container' may not have started — check: docker logs $container"
        $failed += $container
    }
}

# ── Final summary ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  FilamentOS is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "  Access your services:" -ForegroundColor White
Write-Host "    Spoolman (inventory)  →  http://${HOST_IP}:${PORT_SPOOLMAN}" -ForegroundColor Cyan
Write-Host "    FilamentOS Dashboard  →  http://${HOST_IP}:${PORT_DASHBOARD}" -ForegroundColor Cyan

$bIdx = 1
foreach ($printer in $printers) {
    if ($printer.Type -eq "creality_cfs") {
        $port = $printer.BridgePort
        Write-Host "    $($printer.Name) Bridge UI      →  http://${HOST_IP}:${port}" -ForegroundColor Cyan
        $bIdx++
    }
}

Write-Host ""
Write-Host "  IMPORTANT — Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Open Spoolman at http://${HOST_IP}:${PORT_SPOOLMAN}" -ForegroundColor White
Write-Host "     Go to Settings → Custom Fields and add these fields for Spool:" -ForegroundColor Gray
Write-Host "       • cfs_rfid    (Text)" -ForegroundColor Gray
Write-Host "       • cfs_slot    (Text)" -ForegroundColor Gray
Write-Host "       • cfs_printer (Text)" -ForegroundColor Gray
Write-Host "       • cfs_last_seen (Text)" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Add your filament spools to Spoolman" -ForegroundColor White
Write-Host ""
Write-Host "  3. Install SpoolmanNFC.apk on your Android phone" -ForegroundColor White
Write-Host "     Set the Spoolman URL to: http://${HOST_IP}:${PORT_SPOOLMAN}" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Tag your spool rings with NFC stickers using the app" -ForegroundColor White
Write-Host ""
Write-Host "  See README.md for full documentation." -ForegroundColor DarkGray
Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
