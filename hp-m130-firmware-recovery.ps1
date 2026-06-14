<#
.SYNOPSIS
  Prepare and launch HP LaserJet MFP M129-M134 firmware recovery over network.

.NOTES
  Author: Alexey Kagansky
  GitHub: https://github.com/ale4ko69/
  Created: 2026-06-14
  License: MIT

.DESCRIPTION
  This script is for HP LaserJet Pro MFP M130fn/fw/nw, M132*, and M134* devices
  that are stuck on "Ready 2 Download".

  It:
    1. Checks the printer web UI and RAW print port.
    2. Creates a Windows RAW TCP/IP printer queue on port 9100.
    3. Downloads the official HP firmware updater from HP support APIs.
    4. Verifies the updater is signed by HP Inc.
    5. Launches the HP firmware updater so you can choose the RAW queue and click
       "Send Firmware".

  The script intentionally does not raw-send arbitrary firmware files by default.
  The HP updater knows the correct payload and recovery sequence.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')]
  [string] $PrinterIp,

  [string] $QueueName,

  [string] $WorkDir,

  [switch] $SkipDownload,

  [switch] $LaunchUpdater
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FirmwareFileName = 'M129_Series_FW_Update-20220414.exe'
$FirmwareUrl = 'https://ftp.hp.com/pub/softlib/software13/FW_CPE_Consumer/LJ_M130/M129_Series_FW_Update-20220414.exe'
$ExpectedSha256 = '4C23D02906060443DF49415360F7E4C9117C739899721182EE4939CF22D47ACD'

if (-not $QueueName) {
  $QueueName = "HP M130fn RAW $PrinterIp"
}

if (-not $WorkDir) {
  $baseDir = $PSScriptRoot
  if (-not $baseDir) {
    $baseDir = (Get-Location).Path
  }
  $WorkDir = Join-Path $baseDir 'hp-firmware-work'
}

function Write-Step {
  param([string] $Message)
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-TcpPort {
  param(
    [string] $HostName,
    [int] $Port
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $iar = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(3000, $false)) {
      return $false
    }
    $client.EndConnect($iar)
    return $true
  }
  catch {
    return $false
  }
  finally {
    $client.Close()
  }
}

function Get-HpLaserJetDriverName {
  $preferred = @(
    'HP LaserJet MFP M129-M134 PCLm-S',
    'Microsoft IPP Class Driver',
    'Microsoft enhanced Point and Print compatibility driver'
  )

  foreach ($name in $preferred) {
    if (Get-PrinterDriver -Name $name -ErrorAction SilentlyContinue) {
      return $name
    }
  }

  $candidate = Get-PrinterDriver |
    Where-Object { $_.Name -match 'HP|LaserJet|PCL|IPP' } |
    Select-Object -First 1 -ExpandProperty Name

  if (-not $candidate) {
    throw 'No suitable Windows printer driver found. Install the HP M129-M134 driver package or HP Smart first.'
  }

  return $candidate
}

function Ensure-RawQueue {
  param(
    [string] $Ip,
    [string] $Name
  )

  $portName = "IP_${Ip}_RAW9100"

  if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating RAW TCP/IP port $portName -> ${Ip}:9100"
    Add-PrinterPort -Name $portName -PrinterHostAddress $Ip -PortNumber 9100
  }
  else {
    Write-Host "RAW port already exists: $portName"
  }

  if (-not (Get-Printer -Name $Name -ErrorAction SilentlyContinue)) {
    $driver = Get-HpLaserJetDriverName
    Write-Host "Creating printer queue '$Name' with driver '$driver'"
    Add-Printer -Name $Name -DriverName $driver -PortName $portName
  }
  else {
    Write-Host "Printer queue already exists: $Name"
  }

  Get-Printer -Name $Name | Select-Object Name, DriverName, PortName, PrinterStatus
}

function Download-Firmware {
  param([string] $Destination)

  if (Test-Path $Destination) {
    $hash = (Get-FileHash $Destination -Algorithm SHA256).Hash
    if ($hash -eq $ExpectedSha256) {
      Write-Host "Firmware updater already downloaded and hash matches."
      return
    }

    Write-Warning "Existing file hash does not match; downloading a fresh copy."
    Remove-Item -LiteralPath $Destination -Force
  }

  Write-Host "Downloading official HP firmware updater:"
  Write-Host $FirmwareUrl
  Invoke-WebRequest -Uri $FirmwareUrl -OutFile $Destination -UseBasicParsing
}

function Verify-Firmware {
  param([string] $Path)

  if (-not (Test-Path $Path)) {
    throw "Firmware updater not found: $Path"
  }

  $hash = (Get-FileHash $Path -Algorithm SHA256).Hash
  Write-Host "SHA256: $hash"
  if ($hash -ne $ExpectedSha256) {
    throw "Firmware updater SHA256 mismatch. Expected $ExpectedSha256"
  }

  $signature = Get-AuthenticodeSignature $Path
  Write-Host "Signature status: $($signature.Status)"
  if ($signature.Status -ne 'Valid') {
    throw "Firmware updater signature is not valid: $($signature.Status)"
  }

  $subject = $signature.SignerCertificate.Subject
  Write-Host "Signer: $subject"
  if ($subject -notmatch 'O=HP Inc\.|CN=HP Inc\.') {
    throw "Firmware updater is signed, but not by HP Inc.: $subject"
  }
}

Write-Step "Preparing work folder"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$firmwarePath = Join-Path $WorkDir $FirmwareFileName
Write-Host "WorkDir: $WorkDir"

Write-Step "Checking printer connectivity"
$webOk = Test-TcpPort -HostName $PrinterIp -Port 80
$rawOk = Test-TcpPort -HostName $PrinterIp -Port 9100
Write-Host "HTTP 80:  $webOk"
Write-Host "RAW 9100: $rawOk"

if (-not $rawOk) {
  throw "Port 9100 is not reachable on $PrinterIp. Check printer IP/network before firmware recovery."
}

Write-Step "Ensuring RAW printer queue"
Ensure-RawQueue -Ip $PrinterIp -Name $QueueName | Format-List

Write-Step "Getting official HP firmware updater"
if ($SkipDownload -and -not (Test-Path $firmwarePath)) {
  [string[]] $localCandidates = @(
    (Join-Path $PSScriptRoot $FirmwareFileName),
    (Join-Path (Get-Location).Path $FirmwareFileName)
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

  if ($localCandidates.Count -gt 0) {
    Write-Host "Using existing local firmware updater: $($localCandidates[0])"
    Copy-Item -LiteralPath $localCandidates[0] -Destination $firmwarePath -Force
  }
}
if (-not $SkipDownload) {
  Download-Firmware -Destination $firmwarePath
}
Verify-Firmware -Path $firmwarePath

Write-Step "Next manual step"
Write-Host "Firmware updater path:"
Write-Host $firmwarePath -ForegroundColor Yellow
Write-Host ""
Write-Host "In the HP updater, select this queue:"
Write-Host $QueueName -ForegroundColor Yellow
Write-Host ""
Write-Host "Then click 'Send Firmware'. During Downloading/Erasing/Programming:"
Write-Host "  - do not power off the printer"
Write-Host "  - do not close the updater"
Write-Host "  - wait for the printer to reboot by itself"

if ($LaunchUpdater) {
  Write-Step "Launching HP firmware updater"
  Start-Process -FilePath $firmwarePath
}
else {
  Write-Host ""
  Write-Host "Run again with -LaunchUpdater to open it automatically."
}
