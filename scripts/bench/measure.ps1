# Compares warm in-world windows of two VIctory logs (frame time and submission waits).
# Usage: .\measure.ps1 -Log run-new.log -BaselineLog run-old.log [-Survey]
param(
    [Parameter(Mandatory)][string]$Log,
    [Parameter(Mandatory)][string]$BaselineLog,
    [ValidateRange(1, 256)][int]$Windows = 8,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 360,
    [ValidateRange(0, [int]::MaxValue)][int]$GameProcessId = 0,
    [int]$MinDraws = 4600,
    [int]$MaxDraws = 5350,
    [int]$MinDropped = 300,
    [int]$MaxDropped = 380,
    [switch]$Survey
)

$ErrorActionPreference = 'Stop'
if ($MinDraws -gt $MaxDraws -or $MinDropped -gt $MaxDropped) {
    throw 'Each minimum must be less than or equal to its maximum.'
}

function Get-Median($Values) {
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $lower = [math]::Floor(($sorted.Count - 1) / 2)
    $upper = [math]::Floor($sorted.Count / 2)
    return [math]::Round(($sorted[$lower] + $sorted[$upper]) / 2, 2)
}

function Get-WarmWindows([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $reads = [Collections.Generic.List[double]]::new()
    $totals = [Collections.Generic.List[double]]::new()
    $stale = [Collections.Generic.List[double]]::new()
    $inflight = [Collections.Generic.List[double]]::new()
    $frameSamples = [Collections.Generic.List[double]]::new()
    $staleReasons = [Collections.Generic.List[string]]::new()
    $consecutive = 0
    rg -a -n 'fps, .* ms/frame|of the waiting for the card in settles|submissions sent ahead per frame|frame sample|CPU changes wait for shader writes' -- $Path |
        ForEach-Object {
            if ($_ -match 'of the waiting for the card in settles.*title memory changed under shader writes ([\d.]+), title memory read ([\d.]+),.*lists in the air ([\d.]+),') {
                $stale.Add([double]$Matches[1])
                $reads.Add([double]$Matches[2])
                $inflight.Add([double]$Matches[3])
            } elseif ($_ -match 'submissions sent ahead per frame: .*?([\d.]+) ms waiting for the card in them') {
                $totals.Add([double]$Matches[1])
            } elseif ($_ -match 'frame sample.*frame_us=(\d+)') {
                $frameSamples.Add([double]$Matches[1] / 1000)
            } elseif ($_ -match 'CPU changes wait for shader writes.*reason="([^"]+)"') {
                $staleReasons.Add($Matches[1])
            } elseif ($_ -match '^(\d+):.*?([\d.]+) ms/frame.*\), (\d+) draws/frame, dropped (\d+) without a host pipeline \((\d+) being made\)') {
                $line, $ms, $draws, $dropped, $pending = $Matches[1..5]
                if ([int]$draws -ge $MinDraws -and [int]$draws -le $MaxDraws -and
                    [int]$dropped -ge $MinDropped -and [int]$dropped -le $MaxDropped -and
                    [int]$pending -eq 0 -and $reads.Count -gt 0 -and $reads.Count -eq $totals.Count) {
                    $consecutive++
                    if ($consecutive -ge 3) {
                        [pscustomobject]@{
                            Line = [int]$line
                            FrameMs = [double]$ms
                            Draws = [int]$draws
                            Dropped = [int]$dropped
                            ReadMs = $reads.ToArray()
                            TotalMs = $totals.ToArray()
                            StaleMs = $stale.ToArray()
                            InflightMs = $inflight.ToArray()
                            FrameSamples = $frameSamples.ToArray()
                            StaleReasons = $staleReasons.ToArray()
                        }
                    }
                } else {
                    $consecutive = 0
                }
                $reads.Clear()
                $totals.Clear()
                $stale.Clear()
                $inflight.Clear()
                $frameSamples.Clear()
                $staleReasons.Clear()
            }
        }
}

function Get-Summary($Rows) {
    $frames = @($Rows.FrameSamples | Sort-Object)
    $p95 = if ($frames.Count -gt 0) {
        [math]::Round($frames[[math]::Ceiling(0.95 * $frames.Count) - 1], 2)
    }
    $reasonCounts = [ordered]@{}
    $Rows.StaleReasons | Group-Object | Sort-Object Count -Descending | ForEach-Object {
        $reasonCounts[$_.Name] = $_.Count
    }
    return [ordered]@{
        windows = $Rows.Count
        first_line = $Rows[0].Line
        last_line = $Rows[-1].Line
        frame_ms = Get-Median $Rows.FrameMs
        frame_sample_count = $frames.Count
        present_interval_p50_ms = Get-Median $frames
        present_interval_p95_ms = $p95
        draws = Get-Median $Rows.Draws
        dropped = Get-Median $Rows.Dropped
        title_read_wait_ms = Get-Median $Rows.ReadMs
        write_conflict_wait_ms = Get-Median $Rows.StaleMs
        in_flight_limit_wait_ms = Get-Median $Rows.InflightMs
        total_submission_wait_ms = Get-Median $Rows.TotalMs
        write_conflict_reasons = $reasonCounts
    }
}

$baseline = @(Get-WarmWindows $BaselineLog | Select-Object -First $Windows)
if ($baseline.Count -lt $Windows) {
    throw "Baseline has only $($baseline.Count) qualifying gameplay windows."
}

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    $current = @(Get-WarmWindows $Log | Select-Object -First $Windows)
    if ($current.Count -ge $Windows) { break }
    if ($GameProcessId -gt 0 -and -not (Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue)) {
        throw "The title exited with only $($current.Count) qualifying gameplay windows. Inspect $Log."
    }
    Start-Sleep -Seconds 5
} while ([DateTime]::UtcNow -lt $deadline)

if ($current.Count -lt $Windows) {
    throw "Timed out with only $($current.Count) qualifying gameplay windows. Inspect $Log."
}

$before = Get-Summary $baseline
$after = Get-Summary $current
$passes = $after.title_read_wait_ms -le 5 -and $after.frame_ms -lt $before.frame_ms
[pscustomobject]@{
    baseline = $before
    current = $after
    submission_fix_passes = $passes
} | ConvertTo-Json -Depth 5
if (-not $Survey -and -not $passes) { exit 1 }
