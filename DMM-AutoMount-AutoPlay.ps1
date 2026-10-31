# DMM companion v1.6: wait for a new mod enable; keep helper on top; wait 35 seconds, tap E, then minimize.
# wait for DMM to report Mounted, then click DMM's Start/Launch Game control.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$EnableWaitSeconds = 4
$GameReadyDelaySeconds = 35
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DmmGameInput {
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public UIntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION U; }
    [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr handle, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll", SetLastError=true)] private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    public static bool SetTopmost(IntPtr handle, bool topmost) {
        // SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE: change stacking without stealing game input.
        return SetWindowPos(handle, new IntPtr(topmost ? -1 : -2), 0, 0, 0, 0, 0x0013u);
    }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    public static uint SendScanCode(ushort scan, bool down) {
        INPUT item = new INPUT(); item.type = 1; item.U.ki.wVk = 0; item.U.ki.wScan = scan;
        item.U.ki.dwFlags = 0x0008u | (down ? 0u : 0x0002u); item.U.ki.time = 0; item.U.ki.dwExtraInfo = UIntPtr.Zero;
        return SendInput(1, new INPUT[] { item }, Marshal.SizeOf(typeof(INPUT)));
    }
}
'@

function Select-File([string]$title, [string]$filter) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $title; $dialog.Filter = $filter; $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $dialog.FileName
}
function Select-Folder([string]$title) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $title; $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $dialog.SelectedPath
}
function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start(); $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port; $listener.Stop()
    return $port
}
function Get-DmmPage([int]$Port) {
    try {
        $pages = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
        return $pages | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl } | Select-Object -First 1
    } catch { return $null }
}
function Invoke-DmmPageJs([string]$WebSocketUrl, [string]$Expression) {
    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    [void]($socket.ConnectAsync([Uri]$WebSocketUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult())
    try {
        $requestId = Get-Random -Minimum 1000 -Maximum 2000000000
        $request = @{ id = $requestId; method = 'Runtime.evaluate'; params = @{ expression = $Expression; awaitPromise = $true; returnByValue = $true } } | ConvertTo-Json -Depth 6 -Compress
        $bytes = [Text.Encoding]::UTF8.GetBytes($request)
        [void]($socket.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult())
        do {
            $builder = New-Object System.Text.StringBuilder
            do {
                $buffer = New-Object byte[] 8192
                $part = $socket.ReceiveAsync([ArraySegment[byte]]::new($buffer), [Threading.CancellationToken]::None).GetAwaiter().GetResult()
                [void]$builder.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $part.Count))
            } while (-not $part.EndOfMessage)
            $message = $builder.ToString() | ConvertFrom-Json
        } while ($message.id -ne $requestId)
        if ($message.error) { throw $message.error.message }
        if ($message.result.exceptionDetails) {
            $reason = $message.result.exceptionDetails.exception.description
            if (-not $reason) { $reason = $message.result.exceptionDetails.text }
            throw $reason
        }
        return $message.result.result.value
    } finally { $socket.Dispose() }
}
function Get-PageText([string]$WebSocketUrl) {
    return Invoke-DmmPageJs $WebSocketUrl 'document.body ? document.body.innerText : ""'
}
function Get-EnabledCount([string]$Text) {
    if ($Text -match '(?i)(\d+)\s+of\s+\d+\s+mods?\s+enabled') { return [int]$matches[1] }
    return -1
}
function Get-VisibleControls([string]$WebSocketUrl) {
    $js = 'JSON.stringify(Array.from(document.querySelectorAll("button,[role=button],[tabindex]")).filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0}).map(e=>({text:(e.getAttribute("aria-label")||e.getAttribute("title")||e.innerText||e.textContent||"").trim().replace(/\s+/g," "),disabled:!!e.disabled})))'
    return (Invoke-DmmPageJs $WebSocketUrl $js) | ConvertFrom-Json
}

function Wait-ForGameAndPressE {
    $consoleHandle = [DmmGameInput]::GetConsoleWindow()
    $eTapSent = $false
    try {
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [void][DmmGameInput]::ShowWindowAsync($consoleHandle, 9)
            if (-not [DmmGameInput]::SetTopmost($consoleHandle, $true)) { throw 'Could not keep the helper on top.' }
        }
        $launchTimer = [Diagnostics.Stopwatch]::StartNew()
        Write-Host 'Timer started. Waiting for CrimsonDesert.exe to open...' -ForegroundColor Yellow
        $game = $null
        for ($i = 0; $i -lt 300 -and -not $game; $i++) {
            $game = Get-Process -Name 'CrimsonDesert' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
            if (-not $game) {
                if (($i % 5) -eq 0) { Write-Host "Game startup: $($launchTimer.Elapsed.ToString('mm\:ss'))" }
                Start-Sleep -Seconds 1
                if ($consoleHandle -ne [IntPtr]::Zero) { [void][DmmGameInput]::SetTopmost($consoleHandle, $true) }
            }
        }
        if (-not $game) { throw 'CrimsonDesert.exe window did not appear; E was not sent.' }

        $game.Refresh()
        Write-Host "Game window appeared after $($launchTimer.Elapsed.ToString('mm\:ss')). Starting the $GameReadyDelaySeconds-second ready timer..." -ForegroundColor Green
        for ($remaining = $GameReadyDelaySeconds; $remaining -gt 0; $remaining--) {
            if (($remaining % 5) -eq 0 -or $remaining -le 5) { Write-Host "E press in $remaining seconds..." }
            Start-Sleep -Seconds 1
            if ($consoleHandle -ne [IntPtr]::Zero) { [void][DmmGameInput]::SetTopmost($consoleHandle, $true) }
            $game.Refresh()
            if ($game.HasExited) { throw 'The game closed during loading; E was not sent.' }
        }
        $handle = $game.MainWindowHandle
        if ($handle -eq [IntPtr]::Zero) { throw 'The game window disappeared; E was not sent.' }

        # Direct keyboard input to the game only when needed, without restoring
        # its window or retrying activation. Keep the helper visually on top.
        if ([DmmGameInput]::GetForegroundWindow() -ne $handle) {
            [void][DmmGameInput]::SetForegroundWindow($handle)
        }
        if ($consoleHandle -ne [IntPtr]::Zero) { [void][DmmGameInput]::SetTopmost($consoleHandle, $true) }
        if ([DmmGameInput]::GetForegroundWindow() -ne $handle) { throw 'Crimson Desert could not receive keyboard input; E was not sent to another window.' }

        $scanCode = [DmmGameInput]::MapVirtualKey(0x45, 0)
        Write-Host "Sending E at $($launchTimer.Elapsed.ToString('mm\:ss')) after Start Game..." -ForegroundColor Green
        if ([DmmGameInput]::SendScanCode([System.UInt16]$scanCode, $true) -ne 1) { throw 'Windows did not accept the E key-down event.' }
        try { Start-Sleep -Milliseconds 250 }
        finally { [void][DmmGameInput]::SendScanCode([System.UInt16]$scanCode, $false) }
        $eTapSent = $true
        Write-Host 'E tap sent. Minimizing helper now; game stays in front.' -ForegroundColor Green
        if ($consoleHandle -ne [IntPtr]::Zero) { [void][DmmGameInput]::ShowWindowAsync($consoleHandle, 6) }
    } finally {
        if ($consoleHandle -ne [IntPtr]::Zero) {
            # Remove always-on-top even if startup or the E press failed.
            [void][DmmGameInput]::SetTopmost($consoleHandle, $false)
            if (-not $eTapSent) { [void][DmmGameInput]::ShowWindowAsync($consoleHandle, 9) }
        }
    }
}

function Click-DmmControl([string]$WebSocketUrl, [string]$Kind) {
    if ($Kind -eq 'Mount') {
        $pattern = '^(Mount|Mount Mods|Mount Enabled Mods|Mount Changes|Apply Mods|Apply Changes)(\s*\(\d+\))?$'
    } else {
        $pattern = '^(Start Game|Launch Game|Play Game|Launch)(\s*\(\d+\))?$'
    }
    $patternJson = ConvertTo-Json -InputObject $pattern -Compress
    $js = '(function(){const re=new RegExp(' + $patternJson + ',"i");const es=Array.from(document.querySelectorAll("button,[role=button],[tabindex]"));const label=e=>[e.getAttribute("aria-label"),e.getAttribute("title"),e.innerText,e.textContent].find(v=>v&&v.trim())?.trim().replace(/\s+/g," ")||"";const e=es.find(x=>{const r=x.getBoundingClientRect();const s=label(x);return r.width>0&&r.height>0&&!x.disabled&&re.test(s)});if(!e)return JSON.stringify({ok:false,controls:es.map(label).filter(Boolean)});const name=label(e);e.click();return JSON.stringify({ok:true,label:name})})()'
    $result=(Invoke-DmmPageJs $WebSocketUrl $js) | ConvertFrom-Json
    if (-not $result.ok) {
        $controls=($result.controls | Select-Object -Unique | Select-Object -First 25) -join ' | '
        throw "$Kind button not found. Visible controls: $controls"
    }
    return $result.label
}

Write-Host 'Choose DMM.exe. The helper will use the mods folder beside it.' -ForegroundColor Cyan
$dmm = Select-File 'Select Definitive Mod Manager (DMM.exe)' 'DMM.exe|DMM.exe|Applications (*.exe)|*.exe'
if (-not $dmm) { exit }
if ((Split-Path $dmm -Leaf) -ne 'DMM.exe') { throw 'Select DMM.exe.' }
$mods = Join-Path (Split-Path $dmm -Parent) 'mods'
if (-not (Test-Path $mods -PathType Container)) { throw "Could not find the mods folder beside DMM.exe: $mods" }
Write-Host "DMM mods folder: $mods" -ForegroundColor Cyan
if (Get-Process -Name DMM -ErrorAction SilentlyContinue) { throw 'Close DMM first. This helper will open it with its local automation connection enabled.' }

$port=Get-FreePort
$oldArgs=$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--remote-debugging-port=$port"
try { Start-Process -FilePath $dmm | Out-Null } finally { $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=$oldArgs }
Write-Host 'Waiting for DMM...' -ForegroundColor Yellow
$page=$null
for($i=0;$i -lt 90 -and -not $page;$i++){Start-Sleep -Seconds 1;$page=Get-DmmPage $port}
if(-not $page){throw 'DMM did not expose its local page to the helper.'}

$pending=$false; $lastEvent=[DateTime]::MinValue
$current=Get-PageText $page.webSocketDebuggerUrl
$lastEnabledCount=Get-EnabledCount $current
Write-Host 'Ready. Existing enabled or mounted mods will not start the game.' -ForegroundColor Green
Write-Host "Check an unchecked mod box to mount and launch after $EnableWaitSeconds seconds." -ForegroundColor Green
Write-Host 'If every mod is already checked, uncheck one and check it again.'
Write-Host 'Press Ctrl+C to stop.'
while($true){
    Start-Sleep -Seconds 1
    $page=Get-DmmPage $port
    if($page){
        $current=Get-PageText $page.webSocketDebuggerUrl
        $enabledCount=Get-EnabledCount $current
        # The first readable count is a baseline, never a launch request.
        if($lastEnabledCount -ge 0 -and $enabledCount -gt $lastEnabledCount){
            $pending=$true;$lastEvent=[DateTime]::UtcNow
            Write-Host "Detected enabled mods increased to $enabledCount; waiting $EnableWaitSeconds seconds..." -ForegroundColor Yellow
        }
        if($enabledCount -ge 0){$lastEnabledCount=$enabledCount}
    }
    if($pending -and ([DateTime]::UtcNow-$lastEvent).TotalSeconds -ge $EnableWaitSeconds){
        $pending=$false
        $page=Get-DmmPage $port
        if(-not $page){Write-Warning 'DMM page is unavailable; skipped this mod.';continue}
        try {
            $current=Get-PageText $page.webSocketDebuggerUrl
            if($current -match '(?i)NOT\s+MOUNTED'){
                Write-Host 'New mod detected. Clicking DMM Mount...' -ForegroundColor Yellow
                $mountLabel=Click-DmmControl $page.webSocketDebuggerUrl 'Mount'
                Write-Host "Clicked $mountLabel. Waiting for DMM to finish..." -ForegroundColor Yellow
                $mounted=$false
                for($i=0;$i -lt 480;$i++){
                    Start-Sleep -Seconds 1
                    $current=Get-PageText $page.webSocketDebuggerUrl
                    if($current -match '(?i)NOT\s+MOUNTED'){continue}
                    if($current -match '(?i)MOUNTED'){$mounted=$true;break}
                }
                if(-not $mounted){throw 'DMM did not confirm Mounted. The game was not launched.'}
            } elseif($current -notmatch '(?i)MOUNTED') {
                throw 'Could not read DMM mount status. The game was not launched.'
            }
            Write-Host 'DMM reports Mounted. Starting the game...' -ForegroundColor Green
            $launchLabel=Click-DmmControl $page.webSocketDebuggerUrl 'Launch'
            Write-Host "Clicked $launchLabel." -ForegroundColor Green
            Wait-ForGameAndPressE
        } catch { Write-Warning "Automation stopped safely: $($_.Exception.Message)" }
    }
}
