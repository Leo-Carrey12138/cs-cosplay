# Generates the two tiny sound effects used by the game:
#   assets/audio/hit.wav     -> played when you get hit
#   assets/audio/reload.wav  -> played when you fire (magazine / reload click)
#
# NOTE: this file is intentionally pure ASCII so it runs on both
#       Windows PowerShell 5.1 and PowerShell 7 without encoding problems.
# Run:  powershell -ExecutionPolicy Bypass -File tools/generate_sfx.ps1
param(
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\audio')
)

$ErrorActionPreference = 'Stop'
$SampleRate = 22050
$Ascii = [System.Text.Encoding]::ASCII

function Write-Wav {
    param([string]$Path, [double[]]$Samples)

    $dataLen = $Samples.Length * 2
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    $bw.Write($Ascii.GetBytes('RIFF')); $bw.Write([int](36 + $dataLen))
    $bw.Write($Ascii.GetBytes('WAVE'))
    $bw.Write($Ascii.GetBytes('fmt '))
    $bw.Write([int]16)                 # fmt chunk size
    $bw.Write([int16]1)                # PCM
    $bw.Write([int16]1)                # mono
    $bw.Write([int]$SampleRate)
    $bw.Write([int]($SampleRate * 2))  # byte rate
    $bw.Write([int16]2)                # block align
    $bw.Write([int16]16)               # bits per sample
    $bw.Write($Ascii.GetBytes('data')); $bw.Write([int]$dataLen)

    foreach ($s in $Samples) {
        $v = [Math]::Max(-1.0, [Math]::Min(1.0, $s))
        $bw.Write([int16][Math]::Round($v * 32000))
    }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($Path, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
    Write-Host ("  -> {0} ({1} bytes)" -f $Path, (Get-Item $Path).Length)
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$rnd = New-Object System.Random(20240101)

# ---------- hit.wav : low thud + noise burst, 0.30s ----------
$n = [int]($SampleRate * 0.30)
$hit = New-Object 'double[]' $n
for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $SampleRate
    $env = [Math]::Exp(-18.0 * $t)
    $freq = 220.0 - 140.0 * ($t / 0.30)
    $body = [Math]::Sin(2 * [Math]::PI * $freq * $t) * 0.55
    $noise = ($rnd.NextDouble() * 2 - 1) * 0.35
    $hit[$i] = ($body + $noise) * $env
}

# ---------- reload.wav : two magazine clicks, 0.28s ----------
$n2 = [int]($SampleRate * 0.28)
$reload = New-Object 'double[]' $n2
foreach ($start in @(0.0, 0.13)) {
    $s0 = [int]($start * $SampleRate)
    $end = [Math]::Min($n2, $s0 + [int]($SampleRate * 0.09))
    for ($i = $s0; $i -lt $end; $i++) {
        $t = ($i - $s0) / $SampleRate
        $env = [Math]::Exp(-90.0 * $t)
        $reload[$i] += ((($rnd.NextDouble() * 2 - 1) * 0.6) + ([Math]::Sin(2 * [Math]::PI * 900 * $t) * 0.4)) * $env
    }
}

Write-Host 'Generating sound effects...'
Write-Wav -Path (Join-Path $OutDir 'hit.wav') -Samples $hit
Write-Wav -Path (Join-Path $OutDir 'reload.wav') -Samples $reload
Write-Host 'Done.'
