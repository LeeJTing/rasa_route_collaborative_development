[CmdletBinding()]
param(
    [string]$Region = 'southeastasia',
    [string]$Voice = 'ms-MY-YasminNeural',
    [string]$EnglishVoice = 'en-SG-LunaNeural',
    [switch]$RegenerateEnglishNames,
    [string]$FoodIds = '',
    [switch]$DryRun,
    [string]$OutputFormat = 'audio-24khz-160kbitrate-mono-mp3'
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot 'local_food_source.json'
$englishTermsPath = Join-Path $PSScriptRoot 'english_pronunciation_terms.json'
$pronunciationOverridesPath = Join-Path $PSScriptRoot 'pronunciation_overrides.json'
$outputRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'azure_pronunciation_audio'
$runDirectory = Join-Path $outputRoot ('realtime_{0}' -f $Voice)
$audioDirectory = Join-Path $runDirectory 'audio'
$manifestPath = Join-Path $runDirectory 'audio_manifest.csv'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Source file not found: $sourcePath"
}
if (-not (Test-Path -LiteralPath $englishTermsPath)) {
    throw "English pronunciation terms not found: $englishTermsPath"
}

$parsedFoods = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
$foods = @($parsedFoods | ForEach-Object { $_ })
$pronunciationOverrides = Get-Content -LiteralPath $pronunciationOverridesPath -Raw |
    ConvertFrom-Json
$parsedEnglishTerms = Get-Content -LiteralPath $englishTermsPath -Raw | ConvertFrom-Json
$englishTerms = @($parsedEnglishTerms | ForEach-Object { [string]$_ } |
    Sort-Object Length -Descending)
if ($foods.Count -eq 0) {
    throw 'The local food source is empty.'
}
if ($englishTerms.Count -eq 0) {
    throw 'The English pronunciation term list is empty.'
}
if (-not [string]::IsNullOrWhiteSpace($FoodIds)) {
    $foodIdList = [int[]]@($FoodIds.Split(',') | ForEach-Object {
        [int]$_.Trim()
    })
    $requestedIds = [Collections.Generic.HashSet[int]]::new($foodIdList)
    $foods = @($foods | Where-Object { $requestedIds.Contains([int]$_.local_food_id) })
    if ($foods.Count -ne $requestedIds.Count) {
        throw 'One or more requested FoodIds were not found in local_food_source.json.'
    }
}

function ConvertTo-FileSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $normalized = $Value.Normalize([Text.NormalizationForm]::FormD)
    $withoutMarks = -join ($normalized.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark
    })
    $slug = $withoutMarks.ToLowerInvariant().Replace('&', ' and ')
    return [Regex]::Replace($slug, '[^a-z0-9]+', '_').Trim('_')
}

function New-PronunciationSsml {
    param(
        [Parameter(Mandatory = $true)][string]$FoodName,
        [Parameter(Mandatory = $true)][string]$MalayVoice,
        [Parameter(Mandatory = $true)][string]$LocalEnglishVoice,
        [Parameter(Mandatory = $true)][string[]]$EnglishTerms,
        [string]$SpokenText,
        [string]$OverrideVoice
    )

    $escapedTerms = $EnglishTerms | ForEach-Object { [Regex]::Escape($_) }
    $singleTermPattern = '(?:{0})' -f ($escapedTerms -join '|')
    # Detect whether any whole English term occurs in the food name. A mixed
    # name is then spoken by one voice below; this regex does not split audio.
    $pattern = '(?i)(?<![A-Za-z]){0}(?:[\s-]+{0})*(?![A-Za-z])' -f $singleTermPattern
    $matches = [Regex]::Matches($FoodName, $pattern)
    if (-not [string]::IsNullOrWhiteSpace($SpokenText)) {
        $effectiveVoice = if ([string]::IsNullOrWhiteSpace($OverrideVoice)) {
            $MalayVoice
        }
        else {
            $OverrideVoice
        }
        $language = if ($effectiveVoice -eq $LocalEnglishVoice) { 'en-SG' } else { 'ms-MY' }
        $escapedSpokenText = [Security.SecurityElement]::Escape($SpokenText)
        return [pscustomobject]@{
            HasEnglish = $effectiveVoice -eq $LocalEnglishVoice
            Ssml = '<speak version="1.0" xml:lang="{0}"><voice name="{1}" xml:lang="{0}">{2}</voice></speak>' -f $language, $effectiveVoice, $escapedSpokenText
        }
    }
    if ($matches.Count -eq 0) {
        $escapedName = [Security.SecurityElement]::Escape($FoodName)
        return [pscustomobject]@{
            HasEnglish = $false
            Ssml = '<speak version="1.0" xml:lang="ms-MY"><voice name="{0}" xml:lang="ms-MY">{1}</voice></speak>' -f $MalayVoice, $escapedName
        }
    }

    # One voice reads the complete mixed name. Switching voices inside a short
    # food name inserts audible gaps even when adjacent English words are
    # grouped into one segment.
    $escapedName = [Security.SecurityElement]::Escape($FoodName)
    return [pscustomobject]@{
        HasEnglish = $true
        Ssml = '<speak version="1.0" xml:lang="en-SG"><voice name="{0}" xml:lang="en-SG">{1}</voice></speak>' -f $LocalEnglishVoice, $escapedName
    }
}

$characterCount = ($foods | ForEach-Object { $_.food_name.Length } | Measure-Object -Sum).Sum
$voiceListUri = 'https://{0}.tts.speech.microsoft.com/cognitiveservices/voices/list' -f $Region
$synthesisUri = 'https://{0}.tts.speech.microsoft.com/cognitiveservices/v1' -f $Region

$pronunciationPlan = @($foods | ForEach-Object {
    $overrideProperty = $pronunciationOverrides.PSObject.Properties[[string]$_.local_food_id]
    $override = if ($null -eq $overrideProperty) { $null } else { $overrideProperty.Value }
    $pronunciation = New-PronunciationSsml -FoodName ([string]$_.food_name) `
        -MalayVoice $Voice -LocalEnglishVoice $EnglishVoice -EnglishTerms $englishTerms `
        -SpokenText ([string]$override.spoken_text) -OverrideVoice ([string]$override.voice)
    [pscustomobject]@{
        local_food_id = $_.local_food_id
        food_name = $_.food_name
        has_english = [bool]$pronunciation.HasEnglish
        ssml = [string]$pronunciation.Ssml
    }
})
$englishFoodCount = @($pronunciationPlan | Where-Object has_english).Count

if ($DryRun.IsPresent) {
    Write-Host ('Foods:                  {0}' -f $foods.Count)
    Write-Host ('English terms:          {0}' -f $englishTerms.Count)
    Write-Host ('English/mixed refresh:  {0}' -f $englishFoodCount)
    $pronunciationPlan | Where-Object has_english |
        Select-Object local_food_id, food_name, ssml | Format-Table -Wrap
    exit 0
}

$secureKey = Read-Host 'Paste Azure Speech KEY 1 or KEY 2 (input is hidden)' -AsSecureString
$speechKey = [Net.NetworkCredential]::new('', $secureKey).Password
$authHeaders = @{ 'Ocp-Apim-Subscription-Key' = $speechKey }

try {
    Write-Host ('Validating the key for region {0}...' -f $Region)
    try {
        $voices = @(Invoke-RestMethod -Method Get -Uri $voiceListUri -Headers $authHeaders)
    }
    catch {
        throw "Azure rejected the key or region. No audio was synthesized.`n$($_.Exception.Message)"
    }

    if (-not ($voices | Where-Object { $_.ShortName -eq $Voice })) {
        throw "Voice $Voice is not available in region $Region. No audio was synthesized."
    }
    if (-not ($voices | Where-Object { $_.ShortName -eq $EnglishVoice })) {
        throw "English voice $EnglishVoice is not available in region $Region. No audio was synthesized."
    }

    $existingCount = 0
    if (Test-Path -LiteralPath $audioDirectory) {
        $existingCount = @(Get-ChildItem -LiteralPath $audioDirectory -File -Filter '*.mp3').Count
    }

    Write-Host 'Key, region, and voice validation succeeded.'
    Write-Host ''
    Write-Host 'Azure real-time synthesis summary'
    Write-Host ('  Foods:             {0}' -f $foods.Count)
    Write-Host ('  Characters:        {0}' -f $characterCount)
    Write-Host ('  Existing MP3s:     {0}' -f $existingCount)
    Write-Host ('  Voice:             {0}' -f $Voice)
    Write-Host ('  English voice:     {0}' -f $EnglishVoice)
    Write-Host ('  English refresh:   {0}' -f $RegenerateEnglishNames.IsPresent)
    Write-Host ('  English foods:     {0}' -f $englishFoodCount)
    Write-Host ('  Output format:     {0}' -f $OutputFormat)
    Write-Host ('  Region:            {0}' -f $Region)
    Write-Host ''

    $confirmation = Read-Host 'Generate missing MP3 files now? Type y to continue'
    if ($confirmation -cne 'y') {
        Write-Host 'Cancelled. No text-to-speech request was submitted.'
        exit 0
    }

    New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null
    $manifest = [Collections.Generic.List[object]]::new()
    $generatedCount = 0
    $skippedCount = 0

    for ($index = 0; $index -lt $foods.Count; $index++) {
        $food = $foods[$index]
        $foodName = [string]$food.food_name
        $fileName = '{0}_{1}.mp3' -f $food.local_food_id, (ConvertTo-FileSlug $foodName)
        $destination = Join-Path $audioDirectory $fileName
        $pronunciation = $pronunciationPlan[$index]
        $shouldReplace = [bool]$RegenerateEnglishNames -and [bool]$pronunciation.has_english
        $status = 'generated'

        if ((Test-Path -LiteralPath $destination) -and
            ((Get-Item -LiteralPath $destination).Length -gt 0) -and
            -not $shouldReplace) {
            $status = 'existing'
            $skippedCount++
        }
        else {
            $ssml = $pronunciation.ssml
            $requestHeaders = @{
                'Ocp-Apim-Subscription-Key' = $speechKey
                'X-Microsoft-OutputFormat' = $OutputFormat
                'User-Agent' = 'RasaRoutePronunciationGenerator'
            }

            $completed = $false
            $temporaryDestination = '{0}.tmp' -f $destination
            for ($attempt = 1; $attempt -le 4 -and -not $completed; $attempt++) {
                try {
                    Invoke-WebRequest -Method Post -Uri $synthesisUri -Headers $requestHeaders `
                        -ContentType 'application/ssml+xml' -Body $ssml -OutFile $temporaryDestination `
                        -UseBasicParsing
                    Move-Item -LiteralPath $temporaryDestination -Destination $destination -Force
                    $completed = $true
                }
                catch {
                    if (Test-Path -LiteralPath $temporaryDestination) {
                        Remove-Item -LiteralPath $temporaryDestination -Force
                    }
                    if ($attempt -eq 4) {
                        throw "Failed to synthesize ID $($food.local_food_id), $foodName.`n$($_.Exception.Message)"
                    }
                    Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
                }
            }

            $generatedCount++
            Start-Sleep -Milliseconds 250
        }

        $manifest.Add([pscustomobject]@{
            local_food_id = $food.local_food_id
            food_name = $foodName
            audio_file = $fileName
            status = $status
            pronunciation_profile = if ($pronunciation.has_english) { 'mixed-ms-MY-en-SG' } else { 'ms-MY' }
        })
        Write-Progress -Activity 'Generating food pronunciation audio' `
            -Status ('{0}/{1}: {2}' -f ($index + 1), $foods.Count, $foodName) `
            -PercentComplete ((($index + 1) / $foods.Count) * 100)
    }

    Write-Progress -Activity 'Generating food pronunciation audio' -Completed
    $manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8

    Write-Host ''
    Write-Host 'Completed successfully.'
    Write-Host ('Generated this run: {0}' -f $generatedCount)
    Write-Host ('Skipped existing:   {0}' -f $skippedCount)
    Write-Host ('Audio directory:    {0}' -f $audioDirectory)
    Write-Host ('Manifest:           {0}' -f $manifestPath)
}
finally {
    $speechKey = $null
    $authHeaders = $null
    $secureKey = $null
}
