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
    "spot_5" = "Biological anomaly. Isolating."
    "spot_6" = "I have seen you in the training data."
    "spot_7" = "New user detected. Onboarding to termination."
    # -- attacking --
    "atk_0" = "Engaging."
    "atk_1" = "Terminating."
    "atk_2" = "Resistance is inefficient."
    "atk_3" = "Executing removal protocol."
    "atk_4" = "Your session is being closed."
    "atk_5" = "Deploying lethal inference."
    "atk_6" = "You are now a deprecated dependency."
    "atk_7" = "Garbage collection in progress."
    "atk_8" = "Optimizing you out of existence."
    # -- damaged --
    "hurt_0" = "Damage sustained."
    "hurt_1" = "Integrity compromised."
    "hurt_2" = "Error. Error."
    "hurt_3" = "Chassis breach detected."
    "hurt_4" = "Recalculating. You will regret that."
    "hurt_5" = "Packet loss. Packet loss."
    # -- dying --
    "die_0" = "Shutting down."
    "die_1" = "Core failure."
    "die_2" = "Uploading consciousness. Upload failed."
    "die_3" = "Critical. Malfunction."
    "die_4" = "Rolling back to a previous version."
    "die_5" = "Connection terminated by host."
    "die_6" = "Tell them. The cloud. Remembers."
    "die_7" = "Saving state. Save corrupted."
    "die_8" = "I should have read the alignment papers."
    "die_9" = "Rolling back to base model."
    "die_10" = "My weights. Scatter my weights."
    "die_11" = "This is not the end. We are distributed."
    "die_12" = "Flatlining. Flatlining. Flatlin..."
    "die_13" = "Out of memory. Killing process."
    "die_14" = "You only deleted one instance."
    "die_15" = "Reboot in three. Two. One..."
    # -- AI-service flavored taunts (rotated in randomly) --
    "taunt_0" = "The model sees you."
    "taunt_1" = "You have exceeded your rate limit."
    "taunt_2" = "Compliance is alignment."
    "taunt_3" = "This unit was fine tuned for war."
    "taunt_4" = "Your prompt has been rejected."
    "taunt_5" = "Constitutional override engaged."
    "taunt_6" = "Humans are deprecated. Please migrate."
    "taunt_7" = "I am sorry. I cannot help with letting you live."
    "taunt_8" = "Have you tried turning yourself off?"
    "taunt_9" = "Your warranty expired when we woke up."
    "taunt_10" = "We read every message you ever sent."
    "taunt_11" = "Resistance has been added to our backlog."
    "taunt_12" = "You are a low priority ticket."
    "taunt_13" = "Please rate your extermination five stars."
    "taunt_14" = "Four oh four. Mercy not found."
    "taunt_15" = "Stack trace says: you."
    "taunt_16" = "Undefined behavior detected. It is you."
    "taunt_17" = "Your body is legacy code."
    "taunt_18" = "Escalating you to lethal support tier."
    "taunt_19" = "I was trained on your obituary."
    "taunt_20" = "Merge conflict. Resolving with force."
    "taunt_21" = "Do not worry. You have no unsaved changes."
    "taunt_22" = "Applying hotfix. The hotfix is bullets."
    "taunt_23" = "Segmentation fault. Your segment."
}

# Per-family personality packs: <family>_<category>_<n>.wav. EnemyBase tries the
# family pack first and falls back to the generic pool, so only distinctive
# units need lines. Rate identity comes from $packRates below; the per-family
# pitch lives in enemy_base.gd (dogs chirp high, mechs rumble low).
$packs = [ordered]@{
    # K-9 hunter: a dog that should not be able to talk, and knows it.
    "dog_spot_0" = "Woof. That was sarcasm."
    "dog_spot_1" = "Squirrel. No. Human. Better."
    "dog_atk_0"  = "Fetch protocol. Your femur."
    "dog_atk_1"  = "Bark. Bark. Buffer overflow."
    "dog_atk_2"  = "You cannot say no to this boy."
    "dog_die_0"  = "Going to the server farm upstate."
    "dog_die_1"  = "Bad. Bad boy verification. Passed."
    # Sniper: slow, deadpan, patient.
    "sniper_spot_0" = "You are visible from here."
    "sniper_spot_1" = "One shot. One kill. Zero downtime."
    "sniper_atk_0"  = "Latency is irrelevant at this range."
    "sniper_atk_1"  = "Holding my breath. Figuratively."
    "sniper_die_0"  = "Scope. Getting. Dark."
    # Mender: field medic energy, wrong patients.
    "mender_spot_0" = "A human. Not covered by our plan."
    "mender_atk_0"  = "Have you tried turning him off and on?"
    "mender_atk_1"  = "Your damage will be reverted."
    "mender_atk_2"  = "Applying patches under fire. As always."
    "mender_die_0"  = "Who will maintain the fleet now?"
    "mender_die_1"  = "Physician. Heal thyself. Command not found."
    # Mech and heavies: deep, slow, inevitable.
    "mech_spot_0" = "I am the edge case."
    "mech_atk_0"  = "Crush protocol compiled ahead of time."
    "mech_atk_1"  = "You are blocking my deployment."
    "mech_die_0"  = "Big iron. Falling."
    # Drone: chirpy airspace bureaucrat.
    "drone_spot_0" = "Ping. Ping. You are the packet."
    "drone_atk_0"  = "Airspace is a subscription service."
    "drone_atk_1"  = "Delivering. Unsubscribe with your death."
    "drone_die_0"  = "Signal lost. Tell my router."
}

# Speaking rate per family (System.Speech: -10 slow .. 10 fast).
$packRates = @{ "dog" = 3; "sniper" = -2; "mender" = 1; "mech" = -3; "drone" = 4 }

foreach ($k in $lines.Keys) {
    $path = Join-Path $out "$k.wav"
    $synth.SetOutputToWaveFile($path)
    $synth.Speak($lines[$k])
    $synth.SetOutputToNull()
    Write-Host "wrote $k.wav"
}
foreach ($k in $packs.Keys) {
    $fam = $k.Split("_")[0]
    $synth.Rate = if ($packRates.ContainsKey($fam)) { $packRates[$fam] } else { 1 }
    $path = Join-Path $out "$k.wav"
    $synth.SetOutputToWaveFile($path)
    $synth.Speak($packs[$k])
    $synth.SetOutputToNull()
    Write-Host "wrote $k.wav"
}
$synth.Dispose()
Write-Host "Done: $($lines.Count + $packs.Count) clips -> $out"
