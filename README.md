# HP LaserJet M129-M134 Firmware Recovery over Network

By [Alexey Kagansky](https://github.com/ale4ko69/). Created on 2026-06-14.
Released under the MIT License.

Recover an HP LaserJet Pro MFP M130fn/fw/nw, M132*, or M134* printer stuck on:

```text
Ready 2 Download
```

without hunting for a USB printer cable.

## The Problem

Most recovery instructions for this HP LaserJet family say to connect the printer
directly to a computer over USB and run the HP Firmware Update Utility.

That works, but in practice it is annoying:

- these printers use the older square USB Type-B printer connector;
- many people no longer have that cable nearby;
- the printer may already be reachable on the network;
- the HP Embedded Web Server does not expose a firmware upload page for this model.

The useful discovery is that when the printer is still reachable by IP and RAW
printing on TCP port `9100` is open, the official HP firmware updater can recover
the printer through a normal Windows RAW TCP/IP printer queue.

In other words: you may not need USB at all.

## What This Script Does

`hp-m130-firmware-recovery.ps1` prepares the Windows side of the recovery:

1. Checks the printer IP over HTTP port `80`.
2. Checks RAW printing over TCP port `9100`.
3. Creates a Windows RAW TCP/IP printer port.
4. Creates a dedicated printer queue like:

   ```text
   HP M130fn RAW 192.168.1.210
   ```

5. Downloads the official HP firmware updater:

   ```text
   M129_Series_FW_Update-20220414.exe
   ```

6. Verifies the expected SHA256 hash.
7. Verifies the executable is signed by `HP Inc.`
8. Launches the official HP updater if requested.

The script intentionally does **not** raw-send arbitrary firmware files directly
to the printer. The official HP updater handles the correct firmware payload and
recovery flow.

## Supported Scenario

This is intended for printers in the HP LaserJet M129-M134 family, especially:

- HP LaserJet Pro MFP M130fn
- HP LaserJet Pro MFP M130fw
- HP LaserJet Pro MFP M130nw
- related M132 and M134 models covered by HP's `M129_Series_FW_Update-20220414.exe`

It is most useful when:

- the printer display says `Ready 2 Download`;
- the printer still has an IP address;
- `http://<printer-ip>` opens the printer web UI;
- TCP port `9100` is reachable.

## Requirements

- Windows
- PowerShell
- Administrator rights may be needed to create printer ports/queues
- The printer must be reachable on the local network
- A working HP or Microsoft printer driver must already exist on the system

You can install HP Smart or the HP M129-M134 driver package first if Windows has
no suitable printer driver.

## Firmware Binary

Do not commit HP's firmware updater executable to this repository.

The script downloads it from HP at runtime and verifies both:

- SHA256 hash
- Authenticode signature from `HP Inc.`

The `.gitignore` excludes:

```text
M129_Series_FW_Update-*.exe
hp-firmware-work/
```

## Quick Start

Open PowerShell in this repository folder:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\hp-m130-firmware-recovery.ps1 -PrinterIp 192.168.1.210 -LaunchUpdater
```

Replace `192.168.1.210` with your printer IP address.

## Manual Step in the HP Updater

When the HP firmware updater opens, choose the RAW queue created by the script:

```text
HP M130fn RAW <printer-ip>
```

Example:

```text
HP M130fn RAW 192.168.1.210
```

Then click:

```text
Send Firmware
```

## During the Update

The printer may show:

```text
Downloading
Erasing
Programming
```

Do not interrupt it.

- Do not power off the printer.
- Do not close the HP updater.
- Do not disconnect Ethernet.
- Wait for the printer to reboot by itself.

The process can take several minutes. If `Programming` stays on screen for more
than 30 minutes, or if the printer shows an error such as `Fatal Error`, record
the exact message before retrying.

## Prepare Only, Do Not Launch

To prepare the RAW queue and download/verify the updater without opening it:

```powershell
.\hp-m130-firmware-recovery.ps1 -PrinterIp 192.168.1.210
```

The firmware updater will be placed under:

```text
.\hp-firmware-work\M129_Series_FW_Update-20220414.exe
```

## Use an Existing Download

If you already have `M129_Series_FW_Update-20220414.exe` in the repository
folder, you can skip the download:

```powershell
.\hp-m130-firmware-recovery.ps1 -PrinterIp 192.168.1.210 -SkipDownload -LaunchUpdater
```

The script still verifies the SHA256 hash and Authenticode signature before
launching it.

## Troubleshooting

### Port 9100 is not reachable

Check that the printer IP is correct:

```powershell
Test-NetConnection 192.168.1.210 -Port 9100
```

If it fails:

- confirm the printer IP in your router;
- try opening `http://<printer-ip>`;
- check the printer Embedded Web Server for PJL/device access settings;
- restart the printer and try again.

If the network path is unavailable, you may still need a USB A-to-B printer cable.

### The HP updater does not show the RAW queue

Close and reopen the updater after the script creates the queue.

You can also check Windows printers:

```powershell
Get-Printer | Select Name, DriverName, PortName
```

Look for:

```text
HP M130fn RAW <printer-ip>
```

### The updater finishes with a smiley face

That is the successful state. Close the updater and wait for the printer to
return to normal `Ready` state.

## Safety Notes

Firmware recovery is inherently risky if power is interrupted. Use a stable power
source and do not run this during network or power instability.

This project only automates the setup around HP's official updater. It does not
modify the firmware package.

## Credits

Created by [Alexey Kagansky](https://github.com/ale4ko69/) on 2026-06-14 after
recovering an HP LaserJet MFP M130fn that was stuck on `Ready 2 Download`
without a USB Type-B printer cable available.

## License

MIT. See [LICENSE](LICENSE).
