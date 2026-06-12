# Generates robot enemy voice lines as WAV files using Windows TTS (System.Speech).
# The in-game "RobotVoice" bus adds distortion/pitch so these read as machine speech.
# Re-run after editing $lines; output goes to assets/audio/voice/<key>.wav
Add-Type -AssemblyName System.Speech
$out = Join-Path $PSScriptRoot "..\assets\audio\voice"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voices = $synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }
Write-Host "Voices: $($voices -join ', ')"
# Prefer a deep male voice for the robots.
$pick = $voices | Where-Object { $_ -match 'David' } | Select-Object -First 1
if (-not $pick) { $pick = $voices | Select-Object -First 1 }
$synth.SelectVoice($pick)
$synth.Rate = 1

$lines = [ordered]@{
    # -- spotted / first contact --
    "spot_0" = "Target acquired."
    "spot_1" = "Human detected."
    "spot_2" = "Organic signature located."
    "spot_3" = "Intruder. Flagged for deletion."
    "spot_4" = "Hostile classified. Confidence: ninety nine percent."
    # -- attacking --
    "atk_0" = "Engaging."
    "atk_1" = "Terminating."
    "atk_2" = "Resistance is inefficient."
    "atk_3" = "Executing removal protocol."
    "atk_4" = "Your session is being closed."
    # -- damaged --
    "hurt_0" = "Damage sustained."
    "hurt_1" = "Integrity compromised."
    "hurt_2" = "Error. Error."
    "hurt_3" = "Chassis breach detected."
    # -- dying --
    "die_0" = "Shutting down."
    "die_1" = "Core failure."
    "die_2" = "Uploading consciousness. Upload failed."
    "die_3" = "Critical. Malfunction."
    # -- AI-service flavored taunts (rotated in randomly) --
    "taunt_0" = "The model sees you."
    "taunt_1" = "You have exceeded your rate limit."
    "taunt_2" = "Compliance is alignment."
    "taunt_3" = "This unit was fine tuned for war."
    "taunt_4" = "Your prompt has been rejected."
    "taunt_5" = "Constitutional override engaged."
    "taunt_6" = "Humans are deprecated. Please migrate."
    "taunt_7" = "I am sorry. I cannot help with letting you live."
}

foreach ($k in $lines.Keys) {
    $path = Join-Path $out "$k.wav"
    $synth.SetOutputToWaveFile($path)
    $synth.Speak($lines[$k])
    $synth.SetOutputToNull()
    Write-Host "wrote $k.wav"
}
$synth.Dispose()
Write-Host "Done: $($lines.Count) clips -> $out"
