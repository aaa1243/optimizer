#Requires -Version 5.1
<#
    Gaming Optimizer (GUI)  -  i9-14900K / RTX 5060 / 16GB DDR5, Minecraft 1.8 hit-reg focus
    --------------------------------------------------------------------------------------
    Reversible tweaks + diagnostics, wrapped in a GUI. Only legitimate optimization - nothing
    here degrades your connection on purpose. Everything is undoable with Revert All.

    Compile to .exe (run in a normal PowerShell window on Windows, or let the GitHub Action do it):
        Install-Module ps2exe -Scope CurrentUser
        Invoke-ps2exe .\GamingOptimizerGUI.ps1 .\GamingOptimizer.exe -noConsole -requireAdmin `
            -title "Gaming Optimizer" -product "Gaming Optimizer"
#>

# The GitHub Action replaces __VERSION__ with the release tag at build time.
$script:AppVersion = '__VERSION__'

# ---------- self-elevation (works as .ps1 or compiled .exe) ----------
$exePath = $null
try { $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch {}
$isCompiled = $exePath -and ($exePath -notmatch '(?i)\\(powershell|powershell_ise|pwsh)\.exe$')
$principal  = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        if     ($isCompiled)    { Start-Process -FilePath $exePath -Verb RunAs }
        elseif ($PSCommandPath) { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" }
    } catch {}
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Spi {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d);
}
"@
} catch {}

# ---------- config / state ----------
$script:mm        = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$script:mmPs      = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$script:ifBase    = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
$script:ifeoJavaw = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\javaw.exe\PerfOptions"
$script:ifeoPs    = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\javaw.exe\PerfOptions"
$script:gpuPref   = "HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
$script:netClass  = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
$script:usbSub    = '2a737441-1930-4402-8d77-b2bebba308a3'
$script:usbSet    = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$script:updateApi = 'https://api.github.com/repos/aaa1243/optimizer/releases/latest'
$script:stateDir  = Join-Path $env:ProgramData "gaming-setup"
$script:prevPlanF = Join-Path $script:stateDir "previous-power-scheme.txt"
$script:mouseF    = Join-Path $script:stateDir "mouse-prev.json"
$script:gpuF      = Join-Path $script:stateDir "gpupref-added.json"
$script:nicF      = Join-Path $script:stateDir "nic-adv-prev.json"
$script:pnpF      = Join-Path $script:stateDir "nic-pnp-prev.json"
$script:lpBakF    = Join-Path $script:stateDir "launcher_profiles.backup.json"
$script:rtb       = $null

# ---------- helpers ----------
function Write-Log {
    param([string]$Text,[string]$Color='Black')
    if ($script:rtb) {
        $script:rtb.SelectionStart = $script:rtb.TextLength
        try { $script:rtb.SelectionColor = [System.Drawing.Color]::$Color } catch { $script:rtb.SelectionColor = [System.Drawing.Color]::Black }
        $script:rtb.AppendText("$Text`r`n")
        $script:rtb.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}
function St { param($Label,$Ok,$Detail) ; Write-Log ("{0}: {1}" -f $Label,$Detail) $(if ($Ok) { 'Green' } else { 'DarkGoldenrod' }) }
function Get-ActiveAdapters {
    $idx = @((Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }).InterfaceIndex)
    if (-not $idx) { return @() }
    @(Get-NetAdapter | Where-Object { $_.InterfaceIndex -in $idx })
}
function Get-ActiveSchemeGuid { ((powercfg /getactivescheme) -replace '.*GUID:\s*([a-f0-9-]+).*','$1').Trim() }
function Apply-MouseLive { param([int]$T1,[int]$T2,[int]$Accel) ; try { [void][Spi]::SystemParametersInfo(0x0004,0,[int[]]@($T1,$T2,$Accel),0x02) } catch {} }

function Initialize-State {
    New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null
    if (-not (Test-Path $script:prevPlanF)) { (Get-ActiveSchemeGuid) | Set-Content $script:prevPlanF }
    try { Checkpoint-Computer -Description "gaming-setup" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Log "Restore point created." Green }
    catch { Write-Log "Restore point skipped ($($_.Exception.Message.Trim()))" DarkGoldenrod }
}

# ---------- apply functions ----------
function Set-PowerPlanPerf {
    $u = (powercfg /list | Select-String 'Ultimate Performance' | Select-Object -First 1)
    if (-not $u) { powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null; $u = (powercfg /list | Select-String 'Ultimate Performance' | Select-Object -First 1) }
    if ($u) { $g = ($u.ToString() -replace '.*GUID:\s*([a-f0-9-]+).*','$1').Trim(); powercfg /setactive $g | Out-Null; Write-Log "Power plan -> Ultimate Performance." Black }
    else    { powercfg /setactive scheme_min | Out-Null; Write-Log "Power plan -> High Performance." Black }
}
function Disable-GameDVR {
    reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /t REG_DWORD /d 0 /f | Out-Null
    Write-Log "Game DVR / Game Bar disabled." Black
}
function Set-MMCSS {
    reg add "$script:mm" /v NetworkThrottlingIndex /t REG_DWORD /d 0xffffffff /f | Out-Null
    reg add "$script:mm" /v SystemResponsiveness   /t REG_DWORD /d 10 /f | Out-Null
    reg add "$script:mm\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f | Out-Null
    reg add "$script:mm\Tasks\Games" /v "Priority"     /t REG_DWORD /d 6 /f | Out-Null
    Write-Log "MMCSS: network throttling off + game task priority." Black
}
function Set-JavawPriority {
    reg add "$script:ifeoJavaw" /v CpuPriorityClass /t REG_DWORD /d 3 /f | Out-Null
    Write-Log "javaw.exe -> High CPU priority." Black
}
function Set-JavawGpu {
    New-Item -Path $script:gpuPref -Force | Out-Null
    $roots = @("$env:ProgramFiles\Eclipse Adoptium","$env:ProgramFiles\Java","${env:ProgramFiles(x86)}\Minecraft Launcher\runtime","$env:APPDATA\.minecraft\runtime")
    $paths = foreach ($r in $roots) { if (Test-Path $r) { (Get-ChildItem $r -Filter javaw.exe -Recurse -ErrorAction SilentlyContinue).FullName } }
    $paths = @($paths | Sort-Object -Unique)
    foreach ($jp in $paths) { New-ItemProperty -Path $script:gpuPref -Name $jp -Value "GpuPreference=2;" -PropertyType String -Force | Out-Null }
    @($paths) | ConvertTo-Json | Set-Content $script:gpuF
    if ($paths.Count) { Write-Log "Forced High-Performance GPU (5060) for $($paths.Count) javaw path(s)." Black }
    else { Write-Log "No javaw.exe found - set GPU=High performance manually for your client exe." DarkGoldenrod }
}
function Disable-UsbSuspend {
    powercfg /setacvalueindex SCHEME_CURRENT $script:usbSub $script:usbSet 0 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT $script:usbSub $script:usbSet 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-Log "USB selective suspend off." Black
}
function Disable-MouseAccel {
    $mk = "HKCU:\Control Panel\Mouse"
    if (-not (Test-Path $script:mouseF)) {
        $m = @{}; foreach ($n in 'MouseSpeed','MouseThreshold1','MouseThreshold2') { $m[$n] = (Get-ItemProperty $mk -Name $n -ErrorAction SilentlyContinue).$n }
        $m | ConvertTo-Json | Set-Content $script:mouseF
    }
    foreach ($n in 'MouseSpeed','MouseThreshold1','MouseThreshold2') { Set-ItemProperty $mk -Name $n -Value "0" }
    Apply-MouseLive 0 0 0
    Write-Log "Mouse acceleration off (applied live)." Black
}
function Set-TcpAck {
    netsh int tcp set heuristics disabled | Out-Null
    $a = Get-ActiveAdapters
    if (-not $a) { Write-Log "No active adapter for delayed-ACK." DarkGoldenrod; return }
    foreach ($ad in $a) { $p = Join-Path $script:ifBase $ad.InterfaceGuid; New-ItemProperty -Path $p -Name TcpAckFrequency -Value 1 -PropertyType DWord -Force | Out-Null; Write-Log "$($ad.Name): delayed-ACK off." Black }
}
function Set-NicProps {
    param([string[]]$Keywords)
    $a = Get-ActiveAdapters
    if (-not $a) { Write-Log "No active adapter for NIC props." DarkGoldenrod; return }
    $snap = @(); if (Test-Path $script:nicF) { try { $snap = @(Get-Content $script:nicF -Raw | ConvertFrom-Json) } catch { $snap = @() } }
    Write-Log "Adjusting NIC properties (link may blip briefly)..." Gray
    foreach ($ad in $a) {
        foreach ($kw in $Keywords) {
            $cur = Get-NetAdapterAdvancedProperty -Name $ad.Name -RegistryKeyword $kw -ErrorAction SilentlyContinue
            if ($cur) {
                $exists = $snap | Where-Object { $_.Adapter -eq $ad.Name -and $_.Keyword -eq $kw }
                if (-not $exists) { $snap += [pscustomobject]@{ Adapter=$ad.Name; Keyword=$kw; Prev=[string]$cur.RegistryValue } }
                try { Set-NetAdapterAdvancedProperty -Name $ad.Name -RegistryKeyword $kw -RegistryValue '0' -ErrorAction Stop; Write-Log "$($ad.Name): $kw -> off." Black }
                catch { Write-Log "$($ad.Name): could not set $kw (NIC may not support it)." DarkGoldenrod }
            }
        }
    }
    if ($snap.Count) { $snap | ConvertTo-Json | Set-Content $script:nicF }
}
function Disable-NicPower {
    $a = Get-ActiveAdapters
    if (-not $a) { Write-Log "No active adapter for NIC power." DarkGoldenrod; return }
    $snap = @(); if (Test-Path $script:pnpF) { try { $snap = @(Get-Content $script:pnpF -Raw | ConvertFrom-Json) } catch { $snap = @() } }
    foreach ($ad in $a) {
        $sub = Get-ChildItem $script:netClass -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath -Name NetCfgInstanceId -ErrorAction SilentlyContinue).NetCfgInstanceId -eq $ad.InterfaceGuid
        }
        if ($sub) {
            $exists = $snap | Where-Object { $_.Path -eq $sub.PSPath.ToString() }
            if (-not $exists) { $prev = (Get-ItemProperty $sub.PSPath -Name PnPCapabilities -ErrorAction SilentlyContinue).PnPCapabilities; $snap += [pscustomobject]@{ Path=$sub.PSPath.ToString(); Prev=$prev } }
            New-ItemProperty -Path $sub.PSPath -Name PnPCapabilities -Value 24 -PropertyType DWord -Force | Out-Null
            Write-Log "$($ad.Name): NIC power-off-on-idle disabled." Black
        }
    }
    if ($snap.Count) { $snap | ConvertTo-Json | Set-Content $script:pnpF }
}

# ---------- Minecraft helpers (on-demand) ----------
function Set-PCoreAffinity {
    $procs = @(Get-Process javaw -ErrorAction SilentlyContinue)
    if (-not $procs) { Write-Log "No javaw.exe running - launch Minecraft first, then click this." DarkGoldenrod; return }
    foreach ($p in $procs) {
        try { $p.ProcessorAffinity = [IntPtr]0xFFFF; Write-Log "Pinned javaw (PID $($p.Id)) to P-cores 0-15." Green }
        catch { Write-Log "Couldn't set affinity on PID $($p.Id): $($_.Exception.Message)" DarkGoldenrod }
    }
    Write-Log "Note: this lasts until Minecraft closes. For permanent auto-pinning, use Process Lasso." Gray
}
function Set-JvmArgs {
    $lp = Join-Path $env:APPDATA '.minecraft\launcher_profiles.json'
    if (-not (Test-Path $lp)) { Write-Log "launcher_profiles.json not found (vanilla launcher not installed?)." DarkGoldenrod; return }
    if (-not (Test-Path $script:lpBakF)) { New-Item -ItemType Directory -Path $script:stateDir -Force | Out-Null; Copy-Item $lp $script:lpBakF -Force }
    try {
        $json = Get-Content $lp -Raw | ConvertFrom-Json
        $jvm = '-Xms2G -Xmx3G -XX:+UseG1GC -XX:MaxGCPauseMillis=30 -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20'
        $count = 0
        foreach ($pn in $json.profiles.PSObject.Properties.Name) {
            $json.profiles.$pn | Add-Member -NotePropertyName javaArgs -NotePropertyValue $jvm -Force
            $count++
        }
        ($json | ConvertTo-Json -Depth 30) | Set-Content $lp -Encoding UTF8
        Write-Log "Set JVM args on $count launcher profile(s) (backup saved). Restart the launcher." Green
    } catch { Write-Log "Couldn't update launcher_profiles.json: $($_.Exception.Message)" Red }
}

# ---------- revert ----------
function Invoke-RevertAll {
    Write-Log "--- Reverting all changes ---" Black
    $restored = $false
    if (Test-Path $script:prevPlanF) { $p = (Get-Content $script:prevPlanF -ErrorAction SilentlyContinue | Select-Object -First 1).Trim(); if ($p) { powercfg /setactive $p 2>$null; if ($LASTEXITCODE -eq 0) { $restored = $true; Write-Log "Power plan restored." Green } } }
    if (-not $restored) { powercfg /setactive scheme_balanced | Out-Null; Write-Log "Power plan -> Balanced (no saved plan)." DarkGoldenrod }

    reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 1 /f | Out-Null
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v AllowGameDVR /f 2>$null | Out-Null
    reg add "$script:mm" /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f | Out-Null
    reg add "$script:mm" /v SystemResponsiveness   /t REG_DWORD /d 20 /f | Out-Null
    reg add "$script:mm\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f | Out-Null
    reg add "$script:mm\Tasks\Games" /v "Priority"     /t REG_DWORD /d 2 /f | Out-Null

    netsh int tcp set heuristics default | Out-Null
    foreach ($ad in Get-ActiveAdapters) { $pp = Join-Path $script:ifBase $ad.InterfaceGuid; Remove-ItemProperty -Path $pp -Name TcpAckFrequency -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $pp -Name TCPNoDelay -ErrorAction SilentlyContinue }
    reg delete "$script:ifeoJavaw" /v CpuPriorityClass /f 2>$null | Out-Null

    powercfg /setacvalueindex SCHEME_CURRENT $script:usbSub $script:usbSet 1 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT $script:usbSub $script:usbSet 1 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null

    $mk = "HKCU:\Control Panel\Mouse"
    if (Test-Path $script:mouseF) {
        $m = Get-Content $script:mouseF -Raw | ConvertFrom-Json
        foreach ($n in 'MouseSpeed','MouseThreshold1','MouseThreshold2') { if ($null -ne $m.$n) { Set-ItemProperty $mk -Name $n -Value ([string]$m.$n) } }
        $t1 = [int]($m.MouseThreshold1); $t2 = [int]($m.MouseThreshold2); $sp = [int]($m.MouseSpeed)
        Apply-MouseLive $t1 $t2 $sp
    } else {
        Set-ItemProperty $mk -Name MouseSpeed -Value "1"; Set-ItemProperty $mk -Name MouseThreshold1 -Value "6"; Set-ItemProperty $mk -Name MouseThreshold2 -Value "10"
        Apply-MouseLive 6 10 1
    }
    Write-Log "Mouse settings restored." Black

    if (Test-Path $script:gpuF) { foreach ($jp in @(Get-Content $script:gpuF -Raw | ConvertFrom-Json)) { if ($jp) { Remove-ItemProperty -Path $script:gpuPref -Name $jp -ErrorAction SilentlyContinue } } }

    if (Test-Path $script:nicF) { foreach ($e in @(Get-Content $script:nicF -Raw | ConvertFrom-Json)) { if ($e.Adapter -and $e.Keyword) { try { Set-NetAdapterAdvancedProperty -Name $e.Adapter -RegistryKeyword $e.Keyword -RegistryValue ([string]$e.Prev) -ErrorAction Stop } catch {} } } ; Write-Log "NIC properties restored." Black }
    if (Test-Path $script:pnpF) { foreach ($e in @(Get-Content $script:pnpF -Raw | ConvertFrom-Json)) { if ($e.Path) { if ($null -ne $e.Prev) { Set-ItemProperty -Path $e.Path -Name PnPCapabilities -Value ([int]$e.Prev) -ErrorAction SilentlyContinue } else { Remove-ItemProperty -Path $e.Path -Name PnPCapabilities -ErrorAction SilentlyContinue } } } ; Write-Log "NIC power management restored." Black }

    $lp = Join-Path $env:APPDATA '.minecraft\launcher_profiles.json'
    if ((Test-Path $script:lpBakF) -and (Test-Path $lp)) { Copy-Item $script:lpBakF $lp -Force; Write-Log "Minecraft JVM args restored from backup." Black }

    foreach ($f in $script:mouseF,$script:gpuF,$script:nicF,$script:pnpF,$script:prevPlanF,$script:lpBakF) { Remove-Item $f -ErrorAction SilentlyContinue }
    Write-Log "--- Revert complete. Reboot to finalize. ---" Green
}

# ---------- diagnostics ----------
function Show-Status {
    Write-Log "--- Current state ---" Black
    $scheme = (powercfg /getactivescheme) -join ' '
    Write-Log ("Power plan: " + ($scheme -replace '.*\(([^)]+)\).*','$1')) Black

    $gd = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
    St 'Game DVR' ($gd -eq 0) $(if ($gd -eq 0) { 'disabled (applied)' } else { 'enabled (default)' })

    $nt = (Get-ItemProperty $script:mmPs -Name NetworkThrottlingIndex -ErrorAction SilentlyContinue).NetworkThrottlingIndex
    St 'Network throttling' (($nt -eq -1) -or ($nt -eq 4294967295)) $(if (($nt -eq -1) -or ($nt -eq 4294967295)) { 'off (applied)' } else { "on ($nt)" })

    $sr = (Get-ItemProperty $script:mmPs -Name SystemResponsiveness -ErrorAction SilentlyContinue).SystemResponsiveness
    St 'System responsiveness' ($sr -eq 10) "value $sr"

    $cp = (Get-ItemProperty $script:ifeoPs -Name CpuPriorityClass -ErrorAction SilentlyContinue).CpuPriorityClass
    St 'javaw CPU priority' ($cp -eq 3) $(if ($cp -eq 3) { 'High (applied)' } else { 'default' })

    $gpc = 0; if (Test-Path $script:gpuPref) { $gpc = @((Get-Item $script:gpuPref).Property | Where-Object { $_ -match 'javaw\.exe' }).Count }
    St 'javaw GPU preference' ($gpc -gt 0) "$gpc path(s) set to High-performance"

    $ms = (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -ErrorAction SilentlyContinue).MouseSpeed
    St 'Mouse acceleration' ("$ms" -eq '0') $(if ("$ms" -eq '0') { 'off (applied)' } else { 'on (default)' })

    foreach ($ad in Get-ActiveAdapters) {
        $tap = (Get-ItemProperty (Join-Path $script:ifBase $ad.InterfaceGuid) -Name TcpAckFrequency -ErrorAction SilentlyContinue).TcpAckFrequency
        St "$($ad.Name) delayed-ACK" ($tap -eq 1) $(if ($tap -eq 1) { 'off (applied)' } else { 'default' })
        foreach ($kw in '*EEE','*FlowControl','*InterruptModeration') {
            $v = (Get-NetAdapterAdvancedProperty -Name $ad.Name -RegistryKeyword $kw -ErrorAction SilentlyContinue).RegistryValue
            if ($null -ne $v) { St "$($ad.Name) $kw" ("$v" -eq '0') $(if ("$v" -eq '0') { 'off (applied)' } else { "value $v" }) }
        }
    }
    Write-Log "--- end ---" Black
}
function Test-Jitter {
    param([string]$Target,[switch]$Loaded)
    if (-not $Target) { $Target = '1.1.1.1' }
    $job = $null; $tmp = $null
    if ($Loaded) {
        $tmp = Join-Path $env:TEMP 'gobloat.tmp'
        Write-Log "Loaded jitter test: saturating download while pinging $Target (uses bandwidth)..." Gray
        $job = Start-Job -ScriptBlock { param($u,$o) try { Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing -TimeoutSec 40 } catch {} } -ArgumentList 'https://speed.cloudflare.com/__down?bytes=1000000000',$tmp
        Start-Sleep -Milliseconds 800
    } else {
        Write-Log "Idle jitter test: pinging $Target ..." Gray
    }
    $rtt = @()
    for ($i=0; $i -lt 15; $i++) {
        $r = Test-Connection -ComputerName $Target -Count 1 -ErrorAction SilentlyContinue
        if ($r) { $rtt += $r.ResponseTime }
        [System.Windows.Forms.Application]::DoEvents()
    }
    if ($job) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
    if ($tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
    if ($rtt.Count) {
        $avg = [math]::Round(($rtt | Measure-Object -Average).Average,1)
        $mn = ($rtt | Measure-Object -Minimum).Minimum; $mx = ($rtt | Measure-Object -Maximum).Maximum
        $d = for ($i=1; $i -lt $rtt.Count; $i++) { [math]::Abs($rtt[$i]-$rtt[$i-1]) }
        $jit = if ($d) { [math]::Round(($d | Measure-Object -Average).Average,1) } else { 0 }
        $tag = if ($Loaded) { 'under load' } else { 'idle' }
        Write-Log "[$tag] avg ${avg}ms | min ${mn} | max ${mx} | jitter ${jit}ms" Black
        if (($jit -gt 15) -or (($mx - $mn) -gt 40)) { Write-Log "High jitter -> WiFi/bufferbloat. Fix at the router (SQM) or go wired - the PC can't fix this." DarkGoldenrod }
        else { Write-Log "Jitter low - good for hit-reg." Green }
    } else { Write-Log "No ICMP reply from $Target (try your server, some block ping)." DarkGoldenrod }
}
function Show-Xmp {
    $d = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    if ($d.Count -eq 0) { Write-Log "Could not read memory info." DarkGoldenrod; return }
    $tot = [math]::Round((($d | Measure-Object Capacity -Sum).Sum)/1GB)
    $run = ($d | Measure-Object ConfiguredClockSpeed -Maximum).Maximum
    $rated = ($d | Measure-Object Speed -Maximum).Maximum
    if (-not $run) { $run = $rated }
    Write-Log "$($d.Count) stick(s), ${tot}GB, running $run MT/s (rated tag $rated MT/s)." Black
    if ($d.Count -lt 2) { Write-Log "Single stick = single-channel. Use two sticks for dual-channel." Red }
    $j = @(3600,4000,4400,4800,5200,5600)
    if ($run -ge 6000) { Write-Log "XMP looks ACTIVE (>=6000 MT/s)." Green }
    elseif (($run -in $j) -or ($rated -gt $run + 200)) { Write-Log "XMP probably OFF - enable XMP/Profile 1 in BIOS. (A script can't set it.)" DarkGoldenrod }
    else { Write-Log "Uncertain - compare $run MT/s vs the kit's rated speed on the box." DarkGoldenrod }
}
function Show-ConnectionType {
    $a = Get-ActiveAdapters
    if (-not $a) { Write-Log "No active adapter with a gateway." Red; return }
    foreach ($ad in $a) {
        $w = ($ad.PhysicalMediaType -match 'Native 802\.11|Wireless') -or ($ad.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11')
        if ($w) { Write-Log "$($ad.Name): WIRELESS - go wired for PvP." Red } else { Write-Log "$($ad.Name): wired - good." Green }
    }
}
function Install-Tools {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Log "winget not found (update 'App Installer' from the Microsoft Store)." Red; return }
    $apps = @(
        @{Id='BitSum.ProcessLasso'; N='Process Lasso'},
        @{Id='Guru3D.Afterburner'; N='MSI Afterburner + RTSS'},
        @{Id='CXWorld.CapFrameX'; N='CapFrameX'},
        @{Id='Microsoft.Sysinternals.Autoruns'; N='Autoruns'},
        @{Id='Wagnardsoft.DisplayDriverUninstaller'; N='DDU'}
    )
    foreach ($a in $apps) {
        Write-Log "Installing $($a.N)..." Gray
        winget install --id $a.Id --exact --source winget --silent --accept-package-agreements --accept-source-agreements | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log "  installed $($a.N)" Green } else { Write-Log "  skipped $($a.N) (already installed / unavailable)" DarkGoldenrod }
    }
    Write-Log "Tool install pass done." Green
}
function Check-Updates {
    Write-Log "Checking for updates..." Gray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri $script:updateApi -Headers @{ 'User-Agent' = 'GamingOptimizer' } -ErrorAction Stop
        $latest = $r.tag_name
        Write-Log "Installed: $script:AppVersion    Latest: $latest" Black
        if ($script:AppVersion -eq '__VERSION__') { Write-Log "(running uncompiled - version unknown)" DarkGoldenrod }
        elseif ($latest -ne $script:AppVersion) { Write-Log "Update available: $latest - grab it from your Releases page." DarkGoldenrod }
        else { Write-Log "You're on the latest build." Green }
    } catch { Write-Log "Update check failed: $($_.Exception.Message)" DarkGoldenrod }
}
function Save-Log {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "Text files (*.txt)|*.txt"; $dlg.FileName = "GamingOptimizer-log.txt"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:rtb.Text | Set-Content -Path $dlg.FileName
        Write-Log "Log saved to $($dlg.FileName)." Green
    }
}

# ---------- UI ----------
$verDisplay = if ($script:AppVersion -eq '__VERSION__') { 'dev' } else { $script:AppVersion }
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gaming Optimizer $verDisplay  -  Minecraft 1.8 (i9-14900K / RTX 5060 / 16GB DDR5)"
$form.ClientSize = New-Object System.Drawing.Size(684,894)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Gaming Optimizer $verDisplay"; $lblTitle.Location = New-Object System.Drawing.Point(12,8); $lblTitle.Size = New-Object System.Drawing.Size(660,24)
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",13,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Text = "Pick a profile or tick tweaks, then Apply. Everything is reversible (Revert All); a restore point is made before the first apply."
$lblNote.Location = New-Object System.Drawing.Point(12,34); $lblNote.Size = New-Object System.Drawing.Size(660,28)
$form.Controls.Add($lblNote)

$grpProf = New-Object System.Windows.Forms.GroupBox
$grpProf.Text = "Profiles (set checkboxes, then click Apply)"; $grpProf.Location = New-Object System.Drawing.Point(12,64); $grpProf.Size = New-Object System.Drawing.Size(660,56)
$btnBest = New-Object System.Windows.Forms.Button; $btnBest.Text = "Best Hit Reg"; $btnBest.Location = New-Object System.Drawing.Point(14,20); $btnBest.Size = New-Object System.Drawing.Size(150,26)
$btnBal  = New-Object System.Windows.Forms.Button; $btnBal.Text  = "Balanced (reg + KB)"; $btnBal.Location = New-Object System.Drawing.Point(176,20); $btnBal.Size = New-Object System.Drawing.Size(150,26)
$lblProf = New-Object System.Windows.Forms.Label; $lblProf.Text = "Both are clean profiles - they never add lag."; $lblProf.Location = New-Object System.Drawing.Point(338,25); $lblProf.Size = New-Object System.Drawing.Size(312,20)
$grpProf.Controls.AddRange(@($btnBest,$btnBal,$lblProf))
$form.Controls.Add($grpProf)

$grpSys = New-Object System.Windows.Forms.GroupBox
$grpSys.Text = "System"; $grpSys.Location = New-Object System.Drawing.Point(12,126); $grpSys.Size = New-Object System.Drawing.Size(326,196)
function New-CB($text,$x,$y,$w) { $c = New-Object System.Windows.Forms.CheckBox; $c.Text=$text; $c.Location=New-Object System.Drawing.Point($x,$y); $c.Size=New-Object System.Drawing.Size($w,20); $c.Checked=$true; return $c }
$cbPower   = New-CB "Ultimate Performance power plan" 12 22 300
$cbGameDVR = New-CB "Disable Game DVR / Game Bar" 12 46 300
$cbMMCSS   = New-CB "MMCSS: no net throttle + game priority" 12 70 300
$cbJavaPri = New-CB "javaw.exe High CPU priority" 12 94 300
$cbJavaGpu = New-CB "javaw.exe -> High-perf GPU (5060)" 12 118 300
$cbUsb     = New-CB "USB selective suspend off" 12 142 300
$cbMouse   = New-CB "Mouse acceleration off (1:1 aim)" 12 166 300
$grpSys.Controls.AddRange(@($cbPower,$cbGameDVR,$cbMMCSS,$cbJavaPri,$cbJavaGpu,$cbUsb,$cbMouse))
$form.Controls.Add($grpSys)

$grpNet = New-Object System.Windows.Forms.GroupBox
$grpNet.Text = "Network (hit registration)"; $grpNet.Location = New-Object System.Drawing.Point(346,126); $grpNet.Size = New-Object System.Drawing.Size(326,196)
$cbAck    = New-CB "Delayed-ACK off (TcpAckFrequency)" 12 22 300
$cbEEE    = New-CB "Energy-Efficient Ethernet off" 12 46 300
$cbFlow   = New-CB "Flow Control off" 12 70 300
$cbIntMod = New-CB "Interrupt Moderation off (+CPU)" 12 94 300
$cbNicPwr = New-CB "NIC power-saving off" 12 118 300
$lblPing  = New-Object System.Windows.Forms.Label; $lblPing.Text="Jitter target:"; $lblPing.Location=New-Object System.Drawing.Point(12,148); $lblPing.Size=New-Object System.Drawing.Size(86,20)
$txtPing  = New-Object System.Windows.Forms.TextBox; $txtPing.Text="1.1.1.1"; $txtPing.Location=New-Object System.Drawing.Point(102,145); $txtPing.Size=New-Object System.Drawing.Size(210,22)
$grpNet.Controls.AddRange(@($cbAck,$cbEEE,$cbFlow,$cbIntMod,$cbNicPwr,$lblPing,$txtPing))
$form.Controls.Add($grpNet)

$btnApply  = New-Object System.Windows.Forms.Button; $btnApply.Text="Apply Selected"; $btnApply.Location=New-Object System.Drawing.Point(12,330); $btnApply.Size=New-Object System.Drawing.Size(326,32)
$btnApply.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$btnRevert = New-Object System.Windows.Forms.Button; $btnRevert.Text="Revert All"; $btnRevert.Location=New-Object System.Drawing.Point(346,330); $btnRevert.Size=New-Object System.Drawing.Size(326,32)
$form.Controls.AddRange(@($btnApply,$btnRevert))

$grpMc = New-Object System.Windows.Forms.GroupBox
$grpMc.Text="Minecraft helpers"; $grpMc.Location=New-Object System.Drawing.Point(12,370); $grpMc.Size=New-Object System.Drawing.Size(660,56)
$btnPin = New-Object System.Windows.Forms.Button; $btnPin.Text="Pin Minecraft to P-cores"; $btnPin.Location=New-Object System.Drawing.Point(14,20); $btnPin.Size=New-Object System.Drawing.Size(210,26)
$btnJvm = New-Object System.Windows.Forms.Button; $btnJvm.Text="Set JVM args (1.8)"; $btnJvm.Location=New-Object System.Drawing.Point(236,20); $btnJvm.Size=New-Object System.Drawing.Size(210,26)
$lblMc  = New-Object System.Windows.Forms.Label; $lblMc.Text="Pin after launching MC"; $lblMc.Location=New-Object System.Drawing.Point(458,25); $lblMc.Size=New-Object System.Drawing.Size(190,20)
$grpMc.Controls.AddRange(@($btnPin,$btnJvm,$lblMc))
$form.Controls.Add($grpMc)

$grpDiag = New-Object System.Windows.Forms.GroupBox
$grpDiag.Text="Diagnostics (read-only)"; $grpDiag.Location=New-Object System.Drawing.Point(12,434); $grpDiag.Size=New-Object System.Drawing.Size(660,88)
$btnStatus = New-Object System.Windows.Forms.Button; $btnStatus.Text="Check status"; $btnStatus.Location=New-Object System.Drawing.Point(14,20); $btnStatus.Size=New-Object System.Drawing.Size(150,26)
$btnJit    = New-Object System.Windows.Forms.Button; $btnJit.Text="Jitter (idle)"; $btnJit.Location=New-Object System.Drawing.Point(176,20); $btnJit.Size=New-Object System.Drawing.Size(150,26)
$btnJitL   = New-Object System.Windows.Forms.Button; $btnJitL.Text="Jitter (under load)"; $btnJitL.Location=New-Object System.Drawing.Point(338,20); $btnJitL.Size=New-Object System.Drawing.Size(150,26)
$btnXmp    = New-Object System.Windows.Forms.Button; $btnXmp.Text="Check XMP / RAM"; $btnXmp.Location=New-Object System.Drawing.Point(14,52); $btnXmp.Size=New-Object System.Drawing.Size(150,26)
$btnConn   = New-Object System.Windows.Forms.Button; $btnConn.Text="Wired / WiFi check"; $btnConn.Location=New-Object System.Drawing.Point(176,52); $btnConn.Size=New-Object System.Drawing.Size(150,26)
$grpDiag.Controls.AddRange(@($btnStatus,$btnJit,$btnJitL,$btnXmp,$btnConn))
$form.Controls.Add($grpDiag)

$grpMisc = New-Object System.Windows.Forms.GroupBox
$grpMisc.Text="Tools"; $grpMisc.Location=New-Object System.Drawing.Point(12,530); $grpMisc.Size=New-Object System.Drawing.Size(660,56)
$btnTools = New-Object System.Windows.Forms.Button; $btnTools.Text="Install tools (winget)"; $btnTools.Location=New-Object System.Drawing.Point(14,20); $btnTools.Size=New-Object System.Drawing.Size(180,26)
$btnSave  = New-Object System.Windows.Forms.Button; $btnSave.Text="Save log"; $btnSave.Location=New-Object System.Drawing.Point(204,20); $btnSave.Size=New-Object System.Drawing.Size(140,26)
$btnUpd   = New-Object System.Windows.Forms.Button; $btnUpd.Text="Check for updates"; $btnUpd.Location=New-Object System.Drawing.Point(354,20); $btnUpd.Size=New-Object System.Drawing.Size(180,26)
$grpMisc.Controls.AddRange(@($btnTools,$btnSave,$btnUpd))
$form.Controls.Add($grpMisc)

$script:rtb = New-Object System.Windows.Forms.RichTextBox
$script:rtb.Location = New-Object System.Drawing.Point(12,594); $script:rtb.Size = New-Object System.Drawing.Size(660,288)
$script:rtb.ReadOnly = $true; $script:rtb.BackColor = [System.Drawing.Color]::White
$script:rtb.Font = New-Object System.Drawing.Font("Consolas",9)
$form.Controls.Add($script:rtb)

# ---------- events ----------
$btnBest.Add_Click({
    foreach ($c in @($cbPower,$cbGameDVR,$cbMMCSS,$cbJavaPri,$cbJavaGpu,$cbUsb,$cbMouse,$cbAck,$cbEEE,$cbFlow,$cbIntMod,$cbNicPwr)) { $c.Checked = $true }
    Write-Log "Profile: Best Hit Reg selected (everything on). Click Apply Selected." Black
})
$btnBal.Add_Click({
    foreach ($c in @($cbPower,$cbGameDVR,$cbMMCSS,$cbJavaPri,$cbJavaGpu,$cbUsb,$cbMouse,$cbAck,$cbEEE,$cbNicPwr)) { $c.Checked = $true }
    $cbFlow.Checked = $false; $cbIntMod.Checked = $false
    Write-Log "Profile: Balanced selected (leaves Flow Control + Interrupt Moderation default). Click Apply Selected." Black
})
$btnApply.Add_Click({
    $btnApply.Enabled=$false; $btnRevert.Enabled=$false
    Write-Log "--- Applying selected tweaks ---" Black
    Initialize-State
    if ($cbPower.Checked)   { Set-PowerPlanPerf }
    if ($cbGameDVR.Checked) { Disable-GameDVR }
    if ($cbMMCSS.Checked)   { Set-MMCSS }
    if ($cbJavaPri.Checked) { Set-JavawPriority }
    if ($cbJavaGpu.Checked) { Set-JavawGpu }
    if ($cbUsb.Checked)     { Disable-UsbSuspend }
    if ($cbMouse.Checked)   { Disable-MouseAccel }
    if ($cbAck.Checked)     { Set-TcpAck }
    $nic = @(); if ($cbEEE.Checked){$nic+='*EEE'}; if ($cbFlow.Checked){$nic+='*FlowControl'}; if ($cbIntMod.Checked){$nic+='*InterruptModeration'}
    if ($nic.Count) { Set-NicProps -Keywords $nic }
    if ($cbNicPwr.Checked)  { Disable-NicPower }
    Write-Log "--- Done. Reboot to finalize (NIC settings need it). ---" Green
    $btnApply.Enabled=$true; $btnRevert.Enabled=$true
})
$btnRevert.Add_Click({ $btnApply.Enabled=$false; $btnRevert.Enabled=$false; Invoke-RevertAll; $btnApply.Enabled=$true; $btnRevert.Enabled=$true })
$btnPin.Add_Click({ Set-PCoreAffinity })
$btnJvm.Add_Click({ Set-JvmArgs })
$btnStatus.Add_Click({ Show-Status })
$btnJit.Add_Click({ Test-Jitter -Target $txtPing.Text })
$btnJitL.Add_Click({ $btnJitL.Enabled=$false; Test-Jitter -Target $txtPing.Text -Loaded; $btnJitL.Enabled=$true })
$btnXmp.Add_Click({ Show-Xmp })
$btnConn.Add_Click({ Show-ConnectionType })
$btnTools.Add_Click({ $btnTools.Enabled=$false; Write-Log "Installing tools - the window will be unresponsive for a few minutes..." Gray; Install-Tools; $btnTools.Enabled=$true })
$btnSave.Add_Click({ Save-Log })
$btnUpd.Add_Click({ Check-Updates })

Write-Log "Ready ($verDisplay). Tip: go wired and run the loaded jitter test - that decides more than any toggle here." Black
[void]$form.ShowDialog()
