# DMM Auto-Mount and Auto-Play Helper

**Version 1.6 · by elHUDlessG · Windows / PowerShell**

Let the helper handle the wait while Definitive Mod Manager prepares your Crimson Desert mods. After you check an unchecked mod, the helper can ask DMM to mount, wait for it to finish, launch the game, and press **E** once after a countdown.

This is an independent companion helper. **Definitive Mod Manager (DMM) is created by AerowynX.** DMM is a separate required download and is not included. This project does not claim authorship of or ownership of DMM and is not an official DMM or Pearl Abyss release.

- [Nexus Mods page](https://www.nexusmods.com/crimsondesert/mods/3937)
- [Get Definitive Mod Manager](https://www.nexusmods.com/crimsondesert/mods/633)

## Requirements

- Windows with Windows PowerShell 5.1 (`powershell.exe`).
- Crimson Desert configured in DMM.
- DMM installed separately, with a `mods` folder beside `DMM.exe`.

## Run

1. Close DMM and any older copy of this helper.
2. Download and extract the complete source ZIP into a normal folder.
3. Double-click **Start-Automation.cmd**.
4. Choose your existing **DMM.exe**. The helper opens DMM for you.
5. Wait for **Ready**, then check a previously unchecked mod in DMM.

If every mod is already checked, uncheck one, leave it unchecked for at least one second, then check it again. Avoid changing mod selection during an active mount or launch.

This is a standalone helper: do not import its ZIP into DMM. There is no separate build step or Visual Studio requirement. Stop it with **Ctrl+C** in its console or close the helper window.

## Sequence

- Opening the helper establishes the starting enabled-mod count; it does not trigger a launch.
- An increase in enabled mods queues the sequence after a four-second wait.
- If DMM reports **Not Mounted**, the helper clicks its mount control and waits for **Mounted**.
- The helper clicks DMM's game launch control.
- When a `CrimsonDesert.exe` window appears, a **35-second** countdown begins.
- The helper directs input to the game, sends one **E** key-down/key-up pair, and minimizes its console afterward.
- The console is kept on top during the game startup countdown. DMM remains responsible for mod operations and backups.

## Adjust the timing

Open `DMM-AutoMount-AutoPlay.ps1` in a text editor and adjust the numbers near the top:

```powershell
$EnableWaitSeconds = 4
$GameReadyDelaySeconds = 35
```

Save and restart the helper. The second timer begins when the game window appears. It does **not** detect the title screen visually or measure loading completion. Slow PCs may need a longer delay. The helper does not select a save file or load a saved game.

## Source and review notes

All helper source is included in this repository:

| File | Purpose |
| --- | --- |
| `DMM-AutoMount-AutoPlay.ps1` | DMM automation, status polling, launch timing, and E key input |
| `Start-Automation.cmd` | Starts the PowerShell script and keeps errors visible |

The launcher runs Windows PowerShell with `-NoProfile -ExecutionPolicy Bypass` for that invocation; it does not persistently change the execution-policy setting. The script uses `Add-Type` to compile its included C# interop declarations at runtime; there is no prebuilt helper executable to compile or download.

To communicate with DMM, the script starts it with a WebView2 remote-debugging port argument and connects through a local loopback endpoint. It reads DMM's page text and clicks matching mount/launch controls. It uses Windows APIs, including `SendInput`, for the E tap, and console-window APIs for the on-top/minimize behavior.

The helper does not bundle DMM, implement its mod-patching engine, or download additional code. Its operation depends on DMM's visible interface and status labels. Interface changes can require helper updates. If it cannot confirm mounting or direct the key press to the game, it reports an error for that sequence.

## Troubleshooting

- **Close DMM first:** the helper must launch DMM with its automation connection.
- **Missing mods folder:** complete normal DMM setup and confirm the folder exists beside the selected executable.
- **Nothing starts:** wait for Ready, then enable a previously unchecked mod. Existing checked mods and file changes alone do not trigger launch.
- **E arrives too early:** increase `$GameReadyDelaySeconds` and restart.
- **DMM controls/status cannot be read:** report your DMM version and the exact console error. Compatibility with every DMM version is not guaranteed.

## Contributing

Issues and improvements are welcome. Include the DMM version, relevant timing values, exact console message, and steps to reproduce. Remove personal paths or other private information from logs before sharing.

## License and credits

The helper source is available under the [MIT License](LICENSE), copyright 2026 elHUDlessG. You may use, modify, and redistribute the helper under those terms, retaining the copyright and license notice. The license applies to this helper's source, not to DMM or Crimson Desert.

DMM credit: **AerowynX**. Crimson Desert belongs to its respective rights holders.

[Optional support on Buy Me a Coffee](https://www.buymeacoffee.com/elHUDlessG)
