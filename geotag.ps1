<#
Version 1.0.0 - 29.08.2026 - @nurjns
#>

# Paths
$sourceFolder = 'memories'
$targetFolder = 'memories_geotagged'
$jsonFile = 'json\snap_map_places_history.json'
$exiftool = '.\exiftool.exe'

# Create target folder if it doesn't exist
if (-not (Test-Path $targetFolder)) {
	New-Item -ItemType Directory -Path $targetFolder | Out-Null
	Write-Host "📁 Created target directory: $targetFolder"
}

# Function for umlaut conversion and URL encoding
function ConvertUmlautsAndUrlEncode {
	param([string]$str)
	
	# Remove commas
	$str = $str -replace ',', ''

	# Replace umlauts
	$str = $str -replace 'ü', 'ue'
	$str = $str -replace 'Ü', 'Ue'
	$str = $str -replace 'ä', 'ae'
	$str = $str -replace 'Ä', 'Ae'
	$str = $str -replace 'ö', 'oe'
	$str = $str -replace 'Ö', 'Oe'
	$str = $str -replace 'ß', 'ss'

	# Convert spaces to %20
	return $str -replace ' ', '%20'
}

# Load JSON with UTF-8 encoding
$jsonRaw = Get-Content $jsonFile -Raw -Encoding utf8
$json = $jsonRaw | ConvertFrom-Json
$history = $json.'Snap Map Places History'

# Load all JPG and PNG files (excluding overlays)
$files = Get-ChildItem -Path $sourceFolder | Where-Object {
	$_.Extension -match '^\.(jpg|png)$' -and $_.BaseName -notmatch '-overlay'
}

# Resume/Start point prompt (Filename or Date)
$startInput = Read-Host '🔁 If you want to resume from a specific file or date (YYYY-MM-DD), enter it here (or press Enter to start from the beginning)'
$startFound = [string]::IsNullOrWhiteSpace($startInput)
$startAtFile = ''

if (-not $startFound) {
	if ($startInput -match '^\d{4}-\d{2}-\d{2}$') {
		# Start by date
		$match = $files | Where-Object { $_.BaseName -like "$startInput*" } | Select-Object -First 1
		if ($match) {
			$startAtFile = $match.Name
			Write-Host '📆 Resuming from first file with date' $startInput ':' $startAtFile
		} else {
			Write-Host '❗️No file found with date' $startInput '. Starting from the beginning.'
			$startFound = $true
		}
	} else {
		# Start by filename
		if ($files.Name -contains $startInput) {
			$startAtFile = $startInput
		} else {
			Write-Host "❗️File '$startInput' not found in source folder. Starting from the beginning."
			$startFound = $true
		}
	}
}

# Start processing
foreach ($file in $files) {
	if (-not $startFound) {
		if ($file.Name -eq $startAtFile) {
			$startFound = $true
		} else {
			continue
		}
	}

	Write-Host "`n➡️ Processing file: $($file.Name)"

	# Check target file
	$targetFile = Join-Path $targetFolder ($file.BaseName + '_geotagged.jpg')
	if (Test-Path $targetFile) {
		Write-Host "⚠️  $($file.Name) was already processed. Skipping."
		continue
	}

	# Extract date from filename
	$datePart = $file.BaseName -split '_' | Select-Object -First 1
	if (-not ($datePart -match '^\d{4}-\d{2}-\d{2}$')) {
		Write-Host "❌ Invalid date format in filename: $($file.Name)"
		continue
	}

	# Filter entries for date
	$matchingEntries = $history | Where-Object { ($_.Date -split ' ')[0] -eq $datePart }
	if ($matchingEntries.Count -eq 0) {
		Write-Host "❌ No location history entries found for $($file.Name)."
		continue
	}

	# Open photo in default viewer
	$photoProcess = Start-Process -FilePath $file.FullName -PassThru

	if ($matchingEntries.Count -gt 1) {
		Write-Host "📅 Multiple entries found for $datePart"
		for ($i = 0; $i -lt $matchingEntries.Count; $i++) {
			$entry = $matchingEntries[$i]
			Write-Host ($i+1) ':' $entry.Place '–' $entry.'Place Location' '–' $entry.Date
		}
		$choice = Read-Host '❓ Select number or (s)kip'

		# Close photo viewer
		try {
			Start-Sleep -Seconds 1
			$photoProcess.CloseMainWindow() | Out-Null
			Start-Sleep -Seconds 1
			if (!$photoProcess.HasExited) { $photoProcess.Kill() }
		} catch {}

		if ($choice -eq 's') {
			Write-Host '⏩ Skipped.'
			if (Test-Path $targetFile) {
				Remove-Item -Path $targetFile -Force
				Write-Host "🗑️ Deleted existing target file $targetFile."
			}
			continue
		}

		if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchingEntries.Count) {
			$selected = $matchingEntries[[int]$choice - 1]
		} else {
			Write-Host '❌ Invalid input. Skipping.'
			continue
		}
	} else {
		$selected = $matchingEntries[0]
		Write-Host '📍 Entry found:' $selected.Place '–' $selected.'Place Location'
		$confirm = Read-Host '✅ Use this location? (y/n)'

		# Close photo viewer
		try {
			Start-Sleep -Seconds 1
			$photoProcess.CloseMainWindow() | Out-Null
			Start-Sleep -Seconds 1
			if (!$photoProcess.HasExited) { $photoProcess.Kill() }
		} catch {}

		if ($confirm.ToLower() -ne 'y') {
			Write-Host '⏩ Photo skipped.'
			continue
		}
	}

	# Prepare API query
	$placeQuery = "$($selected.Place) $($selected.'Place Location')"
	$encodedQuery = ConvertUmlautsAndUrlEncode $placeQuery
	$apiUrl = 'https://photon.komoot.io/api/?q=' + $encodedQuery

	Write-Host '🔗 API URL:' $apiUrl

	try {
		$response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
		if ($response.features.Count -eq 0) {
			Write-Host '❌ No coordinates found via API.'
			continue
		}
		$coords = $response.features[0].geometry.coordinates
		$lon = [math]::Round($coords[0], 3)
		$lat = [math]::Round($coords[1], 3)
		Write-Host "🌍 Coordinates found: $lat, $lon"
	} catch {
		Write-Host '❌ Error querying API:' $_
		continue
	}

	# Parse timestamp from JSON entry
	$utcString = $selected.Date.Replace(' UTC','')
	$utcTime = [datetime]::ParseExact($utcString, 'yyyy-MM-dd HH:mm:ss', $null, [System.Globalization.DateTimeStyles]::AssumeUniversal)
	$datetime = $utcTime.ToString('yyyy:MM:dd HH:mm:ss')

	# Copy file to destination
	Copy-Item -Path $file.FullName -Destination $targetFile -Force

	# Write EXIF metadata
	& $exiftool `
		-quiet `
		-overwrite_original `
		"-GPSLatitude=$lat" `
		"-GPSLatitudeRef=$(if ($lat -ge 0) {'N'} else {'S'})" `
		"-GPSLongitude=$lon" `
		"-GPSLongitudeRef=$(if ($lon -ge 0) {'E'} else {'W'})" `
		"-DateTimeOriginal=$datetime" `
		"-CreateDate=$datetime" `
		"-ModifyDate=$datetime" `
		"-FileModifyDate=$datetime" `
		"-FileCreateDate=$datetime" `
		"$targetFile"

	if ($LASTEXITCODE -eq 0) {
		Write-Host '✅ Geotagging completed:' $targetFile
	} else {
		Write-Host '❌ Error writing metadata with ExifTool.'
	}
}

[console]::beep(500,200)