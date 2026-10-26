#Requires -Version 5.1
<#[
Offline tutorial speech generation. Save this script as UTF-8 WITH BOM for Windows PowerShell 5.1.
The ETS TUTORIAL_CLIPS array is the only narration source; no network or external packages are used.
]#>
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [ValidateRange(1, 1000)]
    [int]$ExpectedCount = 19
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'entry\src\main\ets\model\TutorialNarration.ets'
$outputDir = Join-Path $projectRoot 'entry\src\main\resources\rawfile\tutorial\zh-CN'
$voiceName = 'Microsoft Huihui Desktop'
$sampleRate = 22050

# Strict UTF-8 decoding rejects malformed source instead of substituting characters.
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$source = [System.IO.File]::ReadAllText($sourcePath, $utf8)
$declarations = [regex]::Matches($source, '\bexport\s+const\s+TUTORIAL_CLIPS\b')
if ($declarations.Count -ne 1) {
    throw 'Expected exactly one exported TUTORIAL_CLIPS declaration.'
}
$arrayMatch = [regex]::Match($source, '(?s)\bexport\s+const\s+TUTORIAL_CLIPS\s*:\s*TutorialClip\[\]\s*=\s*\[(?<body>.*?)\]\s*;')
if (-not $arrayMatch.Success) {
    throw 'Cannot locate the complete typed TUTORIAL_CLIPS array. Review parser after source syntax changes.'
}
$body = $arrayMatch.Groups['body'].Value
# Deliberately accept only plain single-quoted literals, not expressions/escapes/comments.
# Consume the WHOLE body with \G: an unsupported or extra item is an error, never skipped.
$itemPattern = '\G\s*\{\s*id\s*:\s*''(?<id>[a-z][a-z0-9_]*)''\s*,\s*text\s*:\s*''(?<text>[^''\\\r\n]+)''\s*\}\s*(?:,|(?=\s*$))'
$itemRegex = New-Object System.Text.RegularExpressions.Regex($itemPattern)
$clips = New-Object 'System.Collections.Generic.List[object]'
$ids = New-Object 'System.Collections.Generic.HashSet[string]'
$offset = 0
while ($offset -lt $body.Length -and $body.Substring($offset).Trim().Length -gt 0) {
    $item = $itemRegex.Match($body, $offset)
    if (-not $item.Success -or $item.Index -ne $offset) {
        throw "Unsupported TUTORIAL_CLIPS item at array character $offset. Nothing may be silently omitted."
    }
    $id = $item.Groups['id'].Value
    $text = $item.Groups['text'].Value
    if ([string]::IsNullOrWhiteSpace($text) -or -not $ids.Add($id)) {
        throw "Empty text or duplicate clip id: $id"
    }
    $clips.Add([pscustomobject]@{ Id = $id; Text = $text })
    $offset = $item.Index + $item.Length
}
if ($clips.Count -ne $ExpectedCount) {
    throw "TUTORIAL_CLIPS count is $($clips.Count); explicitly expected $ExpectedCount. Review additions/removals, then pass -ExpectedCount with the reviewed count."
}
Write-Host "Parsed all $($clips.Count) clips from $sourcePath"

# Use built-in .NET only. Check RIFF boundaries, PCM format and actual sample energy.
if (-not ('TutorialAudioWaveCheck' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;

public sealed class TutorialAudioWaveInfo {
    public string Id;
    public long Bytes;
    public double Seconds;
    public double Rms;
    public int Peak;
    public long NonZeroSamples;
}

public static class TutorialAudioWaveCheck {
    public static TutorialAudioWaveInfo Read(string path, string id, int rate) {
        using (var stream = File.OpenRead(path))
        using (var reader = new BinaryReader(stream, Encoding.ASCII)) {
            if (stream.Length < 44 || Encoding.ASCII.GetString(reader.ReadBytes(4)) != "RIFF")
                throw new InvalidDataException(id + ": missing RIFF header");
            uint riffSize = reader.ReadUInt32();
            if ((long)riffSize + 8 != stream.Length || Encoding.ASCII.GetString(reader.ReadBytes(4)) != "WAVE")
                throw new InvalidDataException(id + ": invalid RIFF size or WAVE signature");
            bool hasFormat = false, hasData = false;
            long dataStart = 0, dataSize = 0;
            while (stream.Position < stream.Length) {
                if (stream.Length - stream.Position < 8)
                    throw new InvalidDataException(id + ": truncated chunk header");
                string name = Encoding.ASCII.GetString(reader.ReadBytes(4));
                uint size = reader.ReadUInt32();
                long start = stream.Position;
                long end = start + size;
                long paddedEnd = end + (size & 1);
                if (paddedEnd > stream.Length)
                    throw new InvalidDataException(id + ": chunk exceeds RIFF boundary");
                if (name == "fmt ") {
                    if (hasFormat || size < 16)
                        throw new InvalidDataException(id + ": duplicate/short fmt chunk");
                    ushort format = reader.ReadUInt16();
                    ushort channels = reader.ReadUInt16();
                    uint sampleRate = reader.ReadUInt32();
                    uint byteRate = reader.ReadUInt32();
                    ushort blockAlign = reader.ReadUInt16();
                    ushort bits = reader.ReadUInt16();
                    if (format != 1 || channels != 1 || sampleRate != rate || bits != 16 || blockAlign != 2 || byteRate != rate * 2)
                        throw new InvalidDataException(id + ": expected mono, 16-bit PCM, " + rate + " Hz");
                    hasFormat = true;
                } else if (name == "data") {
                    if (hasData || size == 0 || (size % 2) != 0)
                        throw new InvalidDataException(id + ": duplicate/empty/unaligned data chunk");
                    hasData = true;
                    dataStart = start;
                    dataSize = size;
                }
                stream.Position = paddedEnd;
            }
            if (!hasFormat || !hasData)
                throw new InvalidDataException(id + ": missing fmt or data chunk");
            long samples = dataSize / 2, nonZero = 0;
            int peak = 0;
            double sumSquares = 0;
            stream.Position = dataStart;
            for (long i = 0; i < samples; i++) {
                int sample = reader.ReadInt16();
                if (sample != 0) nonZero++;
                peak = Math.Max(peak, Math.Abs(sample));
                sumSquares += (double)sample * sample;
            }
            double seconds = samples / (double)rate;
            double rms = Math.Sqrt(sumSquares / samples);
            if (seconds < 0.25 || seconds > 300 || peak < 100 || rms < 10 || nonZero < samples * 0.01)
                throw new InvalidDataException(id + ": implausible duration or silent/near-silent audio");
            return new TutorialAudioWaveInfo { Id = id, Bytes = stream.Length, Seconds = seconds,
                Rms = rms, Peak = peak, NonZeroSamples = nonZero };
        }
    }
}
'@
}

function Test-AudioSet([string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "Audio directory does not exist: $Directory"
    }
    $actual = @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.wav')
    if ($actual.Count -ne $clips.Count) {
        throw "Resource count mismatch: found $($actual.Count) WAV files, expected $($clips.Count)."
    }
    foreach ($file in $actual) {
        if (-not $ids.Contains($file.BaseName) -or $file.Name -cne ($file.BaseName + '.wav')) {
            throw "Unexpected audio file: $($file.FullName)"
        }
    }
    foreach ($clip in $clips) {
        $path = Join-Path $Directory ($clip.Id + '.wav')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing clip resource: $path"
        }
        [TutorialAudioWaveCheck]::Read($path, $clip.Id, $sampleRate)
    }
}

function Show-AudioReport([object[]]$Results) {
    $Results | Select-Object Id, Bytes,
        @{Name='Seconds'; Expression={ [math]::Round($_.Seconds, 3) }},
        @{Name='Rms'; Expression={ [math]::Round($_.Rms, 2) }}, Peak, NonZeroSamples |
        Format-Table -AutoSize | Out-Host
    $totalBytes = ($Results | Measure-Object -Property Bytes -Sum).Sum
    $totalSeconds = ($Results | Measure-Object -Property Seconds -Sum).Sum
    $longest = $Results | Sort-Object -Property Seconds -Descending | Select-Object -First 1
    Write-Host ('Validated {0}/{1} WAV files: PCM, mono, 16-bit, {2} Hz; all non-silent.' -f $Results.Count, $clips.Count, $sampleRate)
    Write-Host ('Raw resource total: {0} bytes ({1:F3} MiB); duration: {2:F3} seconds; longest: {3} ({4:F3} seconds).' -f $totalBytes, ($totalBytes / 1MB), $totalSeconds, $longest.Id, $longest.Seconds)
    Write-Host 'Structural/sample validation only; this does not constitute listening review or prove text/audio alignment.'
}

if ($ValidateOnly) {
    $results = @(Test-AudioSet $outputDir)
    Show-AudioReport $results
    return
}

# Never overwrite user files, even on rerun. Existing WAVs are checked first.
if (Test-Path -LiteralPath $outputDir) {
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        throw "Output path is not a directory: $outputDir"
    }
    $existingWavs = @(Get-ChildItem -LiteralPath $outputDir -File -Filter '*.wav')
    if ($existingWavs.Count -gt 0) {
        $results = @(Test-AudioSet $outputDir)
        Show-AudioReport $results
        throw 'Existing audio validated but NOT replaced. To rebuild, first review and move existing WAVs to a backup outside the resource directory, then rerun.'
    }
}
foreach ($clip in $clips) {
    if (Test-Path -LiteralPath (Join-Path $outputDir ($clip.Id + '.wav'))) {
        throw "Refusing to overwrite existing path for $($clip.Id)."
    }
}

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$stageDir = $null
try {
    $matchingVoices = @($synth.GetInstalledVoices() | Where-Object {
        $_.Enabled -and $_.VoiceInfo.Name -ceq $voiceName -and $_.VoiceInfo.Culture.Name -ceq 'zh-CN'
    })
    if ($matchingVoices.Count -ne 1) {
        throw "Required enabled zh-CN voice not found: $voiceName. No fallback voice or online TTS is permitted."
    }
    $synth.SelectVoice($voiceName)
    $synth.Rate = -1
    $synth.Volume = 100
    $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
        $sampleRate,
        [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
        [System.Speech.AudioFormat.AudioChannel]::Mono
    )
    [void][System.IO.Directory]::CreateDirectory($outputDir)
    $stageDir = Join-Path $outputDir ('.generation-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($stageDir)
    Write-Host "Offline voice: $voiceName (zh-CN); Rate=-1; Volume=100; SAPI PCM $sampleRate Hz."
    foreach ($clip in $clips) {
        $wavePath = Join-Path $stageDir ($clip.Id + '.wav')
        Write-Host "Synthesizing $($clip.Id)..."
        $synth.SetOutputToWaveFile($wavePath, $format)
        try {
            $synth.Speak($clip.Text)
        } finally {
            $synth.SetOutputToNull()
        }
    }
    # Validate the whole staged set before publishing any output.
    $results = @(Test-AudioSet $stageDir)
    foreach ($clip in $clips) {
        $destination = Join-Path $outputDir ($clip.Id + '.wav')
        if (Test-Path -LiteralPath $destination) {
            throw "Destination appeared during synthesis; refusing to overwrite: $destination"
        }
    }
    foreach ($clip in $clips) {
        # The two-argument File.Move refuses to replace an existing destination.
        [System.IO.File]::Move((Join-Path $stageDir ($clip.Id + '.wav')), (Join-Path $outputDir ($clip.Id + '.wav')))
    }
    $results = @(Test-AudioSet $outputDir)
    Show-AudioReport $results
} finally {
    $synth.Dispose()
    if ($stageDir -and (Test-Path -LiteralPath $stageDir -PathType Container)) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }
}
