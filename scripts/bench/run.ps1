# Runs a VIctory build with the NVIDIA tuning switches and logs to a file.
#
# Usage:
#   .\scripts\bench\run.ps1 -Exe <path to the title's exe> [-Target target] [-Log run.log]
#                           [-Plain] [-Stats] [-Diag] [-NoFetch] [-OldFetch] [-Window]
#                           [-Lists N] [-AutoStart]
#
#   -Plain     none of the default switches below
#   -Stats     diagnostics build at full speed (all counters, no GPU timing)
#   -Diag      diagnostics build with VICTORY_GPU_TIMING=1 and DRED (each list timed alone; slow)
#   -NoFetch   experiment: shader writes to card copies never reach title memory
#   -OldFetch  fetch card copies on the title's queue instead of a copy queue of their own
#   -Window    VICTORY_INDIRECT_WINDOW=1 (measured slower; keep off)
#   -Lists N   VICTORY_LATE_WAIT_LISTS (default 128)
#   -AutoStart presses A once, then holds it for 10 s at a time with 1 s releases,
#              so an automated run gets past start screens without a person
#
# Build the target directory first, for example:
#   $env:CARGO_TARGET_DIR='target-a'; cargo build --release -p victory
param(
    [Parameter(Mandatory)][string]$Exe,
    [string]$Target = 'target',
    [string]$Log = 'run.log',
    [string]$Config = '',
    [switch]$Plain, [switch]$Diag, [switch]$Stats, [switch]$NoFetch, [switch]$OldFetch, [switch]$Window,
    [int]$Lists = 0,
    [switch]$AutoStart
)

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$profile_ = if ($Diag -or $Stats) { 'diag' } else { 'release' }
$victory = Join-Path $root "$Target\$profile_\victory.exe"
if (-not (Test-Path -LiteralPath $victory)) { throw "No build at $victory" }
$env:VICTORY_CONFIG = if ($Config) { $Config } else { Join-Path $root 'victory.toml' }

if (-not $Plain) {
    $env:VICTORY_CARD_BUFFERS_MIN_MB = '1'
    $env:VICTORY_RELAY = '2'
    # Room for every big title buffer's copy on a 16 GB card (default 512).
    $env:VICTORY_CARD_BUFFERS_MB = '2048'
}
if ($NoFetch) { $env:VICTORY_CARD_FETCH = '0' }
if ($OldFetch) { $env:VICTORY_FETCH_QUEUE = '0' }
if ($Window) { $env:VICTORY_INDIRECT_WINDOW = '1' }
if ($Lists -gt 0) { $env:VICTORY_LATE_WAIT_LISTS = "$Lists" }
if ($Diag) { $env:VICTORY_GPU_TIMING = '1'; $env:VICTORY_D3D12_DRED = '1' }

$previousKeys = $env:VICTORY_KEYS
try {
    # Enter maps to the pad's A button. Release between holds so a picker
    # still sees a fresh press.
    if ($AutoStart) {
        $env:VICTORY_KEYS = '3:Enter:0.35,5:Enter:10,16:Enter:10,27:Enter:10,38:Enter:10,49:Enter:10,60:Enter:10,71:Enter:10,82:Enter:10'
    }
    $logPath = [IO.Path]::GetFullPath($Log)
    # cmd's redirection keeps the log as plain bytes (PowerShell's writes UTF-16).
    cmd /c "`"$victory`" run `"$Exe`" --execute > `"$logPath`" 2>&1"
} finally {
    if ($AutoStart) { $env:VICTORY_KEYS = $previousKeys }
}
"exit=$LASTEXITCODE"
