# Gaming Optimizer

A small Windows GUI that applies **reversible** system, GPU, input and network tweaks aimed at
**Minecraft 1.8 hit registration and FPS**, with built-in diagnostics.

Everything it changes is undoable with one click (**Revert All**), and a System Restore point is
created before the first apply. It only does legitimate optimization — it never degrades your
connection to manipulate PvP.

---

## Download & run

Grab the latest `GamingOptimizer.exe` from the [Releases](../../releases/latest) page and run it.
First launch shows SmartScreen's "Windows protected your PC" because the exe is unsigned —
click **More info → Run anyway**. The app asks for administrator rights (needed to change system
settings).

To verify the download, compare its hash against the `.sha256` file on the release:

```powershell
Get-FileHash .\GamingOptimizer.exe -Algorithm SHA256
```

---

## What it changes

All of the following are reversible.

### CPU & system responsiveness
- **Ultimate Performance power plan** (or High Performance fallback) — stops core parking / downclocking.
- **Game DVR / Game Bar disabled** — removes background recording overhead.
- **MMCSS network throttling off** + **system responsiveness raised** + **"Games" task priority bumped** — more CPU and network headroom for the game.
- **javaw.exe → High CPU priority** — 1.8 is single-thread bound.

### GPU
- **javaw.exe forced onto the high-performance GPU** — guarantees your dedicated GPU is used instead of integrated graphics.

### Input
- **Mouse acceleration off** (Enhance Pointer Precision) — 1:1 aim, applied live.
- **USB selective suspend off** — no power-management latency on mouse/keyboard.

### Network (hit registration)
- **Delayed-ACK off** (`TcpAckFrequency`) + TCP heuristics disabled.
- **Energy-Efficient Ethernet off**, **Flow Control off**, **Interrupt Moderation off** — less link jitter.
- **NIC "turn off to save power" disabled**.

### Profiles
- **Best Hit Reg** — ticks everything.
- **Balanced (reg + KB)** — same, but leaves Flow Control and Interrupt Moderation at defaults (a little easier on CPU).

---

## Minecraft helpers
- **Pin Minecraft to P-cores** — sets `javaw.exe` affinity to the first 16 logical processors so the game stays on your CPU's performance cores. Most useful on hybrid Intel CPUs (P-core / E-core), where it keeps the slower efficiency cores from running the game. Click it after launching Minecraft; for permanent auto-pinning, use Process Lasso.
- **Set JVM args (1.8)** — writes recommended Java args (G1GC + a fixed heap) into your vanilla launcher profiles, with a backup. The default heap is conservative; bump it if your system has plenty of RAM to spare. Restart the launcher afterwards.

## Diagnostics (read-only)
- **Check status** — shows which tweaks are currently applied.
- **Jitter (idle)** and **Jitter (under load)** — pings a target while idle, or while saturating your line (the real bufferbloat test). High jitter points to WiFi or bufferbloat, which the PC can't fix.
- **Check XMP / RAM** — reports memory speed and flags if XMP/EXPO looks off or you're running single-channel.
- **Wired / WiFi check** — warns if you're on wireless.

## Tools
- **Install tools (winget)** — Process Lasso, MSI Afterburner + RTSS, CapFrameX, Autoruns, DDU.
- **Save log** and **Check for updates**.

---

## The bigger wins it can't do for you

These matter more than anything the app toggles, and have to be done by hand:

- **Go wired.** A cable beats any tweak for hit-reg consistency.
- **Fix bufferbloat at your router** (SQM / anti-bufferbloat QoS, or fq_codel/CAKE on OpenWrt).
- **Enable XMP/EXPO in BIOS** so your RAM runs at its rated speed instead of the slower JEDEC fallback, and use two sticks for dual-channel.
- **Keep your BIOS and chipset drivers current**, and run your CPU at its manufacturer-default power/voltage settings rather than an unstable overclock or overvolt profile.
- **In your GPU control panel**, set power management to prefer maximum performance, enable the low-latency / anti-lag mode, turn Vsync off, and cap FPS just under your refresh rate. Plug the monitor into the GPU, not the motherboard.
- **OptiFine 1.8.9** + a current Java 8 runtime (e.g. Adoptium Temurin).

The app **detects and reminds** you about these but won't change them, because they can't be done safely from a script.

---

## Building it yourself

The exe is built automatically by GitHub Actions (`.github/workflows/build-exe.yml`) on a Windows
runner — you never need Windows locally. Push a version tag and a release is produced:

```bash
git tag v1.1.0
git push --tags
```

To build by hand on Windows instead:

```powershell
Install-Module ps2exe -Scope CurrentUser
Invoke-ps2exe .\GamingOptimizerGUI.ps1 .\GamingOptimizer.exe -noConsole -requireAdmin -title "Gaming Optimizer"
```

---

## Disclaimer

Provided as-is for personal use. It changes Windows settings and your Minecraft launcher config;
everything is reversible via **Revert All** and a restore point, but use it at your own risk. It
does **not** touch Windows Defender or Windows Update.
