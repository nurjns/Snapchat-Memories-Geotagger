<#
Version 1.1.0 - 2026-10-09 - @nurjns
#>

# Paths
$sourceFolder = 'memories'
$targetFolder = 'memories_geotagged'
$jsonFile = 'json\memories_history.json'
$exiftool = '.\exiftool.exe'

# Maximum deviation in seconds for automatic matching
$toleranceSeconds = 5

$invariant = [System.Globalization.CultureInfo]::InvariantCulture

# Create target folder if it doesn't exist
if (-not (Test-Path $targetFolder)) {
	New-Item -ItemType Directory -Path $targetFolder | Out-Null
	Write-Host "Created target directory: $targetFolder"
}

# Load JSON with UTF-8 encoding
$jsonRaw = Get-Content $jsonFile -Raw -Encoding utf8
$json = $jsonRaw | ConvertFrom-Json
$history = $json.'Saved Media' | Where-Object { $_.'Media Type' -eq 'Image' }

# Load all JPG and PNG files (excluding overlays)
$files = Get-ChildItem -Path $sourceFolder | Where-Object {
	$_.Extension -match '^\.(jpg|png)$' -and $_.BaseName -notmatch '-overlay'
}

# Resume/Start point prompt (Filename or Date)
$startInput = Read-Host 'If you want to resume from a specific file or date (YYYY-MM-DD), enter it here (or press Enter to start from the beginning)'
$startFound = [string]::IsNullOrWhiteSpace($startInput)
$startAtFile = ''

if (-not $startFound) {
	if ($startInput -match '^\d{4}-\d{2}-\d{2}$') {
		$match = $files | Where-Object { $_.BaseName -like "$startInput*" } | Select-Object -First 1
		if ($match) {
			$startAtFile = $match.Name
			Write-Host 'Resuming from first file with date' $startInput ':' $startAtFile
		} else {
			Write-Host 'No file found with date' $startInput '. Starting from the beginning.'
			$startFound = $true
		}
	} else {
		if ($files.Name -contains $startInput) {
			$startAtFile = $startInput
		} else {
			Write-Host "File '$startInput' not found in source folder. Starting from the beginning."
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

	Write-Host "`n-> Processing file: $($file.Name)"

	$targetFile = Join-Path $targetFolder ($file.BaseName + '_geotagged.jpg')
	if (Test-Path $targetFile) {
		Write-Host "WARNING: $($file.Name) was already processed. Skipping."
		continue
	}

	$datePart = $file.BaseName -split '_' | Select-Object -First 1
	if (-not ($datePart -match '^\d{4}-\d{2}-\d{2}$')) {
		Write-Host "ERROR: Invalid date format in filename: $($file.Name)"
		continue
	}

	$matchingEntries = @($history | Where-Object { ($_.Date -split ' ')[0] -eq $datePart })
	if ($matchingEntries.Count -eq 0) {
		Write-Host "ERROR: No location history entries found for $($file.Name)."
		continue
	}

	# Timestamp candidates of the file
	$fileTimes = @(
		$file.LastWriteTime
		$file.LastWriteTimeUtc
		$file.CreationTime
		$file.CreationTimeUtc
	)

	# Automatic matching based on the timestamp
	$selected = $null
	$bestDiff = $null

	foreach ($entry in $matchingEntries) {
		if ([string]::IsNullOrWhiteSpace($entry.Location)) {
			continue
		}

		$entryTime = [datetime]::ParseExact($entry.Date.Replace(' UTC', ''), 'yyyy-MM-dd HH:mm:ss', $invariant, [System.Globalization.DateTimeStyles]::None)

		foreach ($fileTime in $fileTimes) {
			$diff = [math]::Abs(($entryTime - $fileTime).TotalSeconds)
			if ($diff -le $toleranceSeconds -and ($null -eq $bestDiff -or $diff -lt $bestDiff)) {
				$bestDiff = $diff
				$selected = $entry
			}
		}
	}

	if ($null -ne $selected) {
		Write-Host ('Automatic match (' + [math]::Round($bestDiff, 1) + 's deviation):') $selected.Location '-' $selected.Date
	} else {
		$photoProcess = Start-Process -FilePath $file.FullName -PassThru

		if ($matchingEntries.Count -gt 1) {
			Write-Host "No automatic match. Multiple entries found for $datePart"
			for ($i = 0; $i -lt $matchingEntries.Count; $i++) {
				Write-Host ($i + 1) ':' $matchingEntries[$i].Location '-' $matchingEntries[$i].Date
			}
			$choice = Read-Host 'Select number or (s)kip'

			try {
				Start-Sleep -Seconds 1
				$photoProcess.CloseMainWindow() | Out-Null
				Start-Sleep -Seconds 1
				if (-not $photoProcess.HasExited) { $photoProcess.Kill() }
			} catch {}

			if ($choice -eq 's') {
				Write-Host 'Skipped.'
				if (Test-Path $targetFile) {
					Remove-Item -Path $targetFile -Force
				}
				continue
			}

			if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchingEntries.Count) {
				$selected = $matchingEntries[[int]$choice - 1]
			} else {
				Write-Host 'Invalid input. Skipping.'
				continue
			}
		} else {
			$selected = $matchingEntries[0]
			Write-Host 'Entry found:' $selected.Location '-' $selected.Date
			$confirm = Read-Host 'Use this location? (y/n)'

			try {
				Start-Sleep -Seconds 1
				$photoProcess.CloseMainWindow() | Out-Null
				Start-Sleep -Seconds 1
				if (-not $photoProcess.HasExited) { $photoProcess.Kill() }
			} catch {}

			if ($confirm.ToLower() -ne 'y') {
				Write-Host 'Photo skipped.'
				continue
			}
		}
	}

	# Extract the coordinates from the Location field (the two numbers at the end)
	if ($selected.Location -notmatch '(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$') {
		Write-Host 'ERROR: Could not parse location:' $selected.Location
		continue
	}

	$lat = [math]::Round([double]::Parse($matches[1], $invariant), 6)
	$lon = [math]::Round([double]::Parse($matches[2], $invariant), 6)

	if ($lat -lt -90 -or $lat -gt 90 -or $lon -lt -180 -or $lon -gt 180) {
		Write-Host "ERROR: Coordinates out of valid range: $lat, $lon"
		continue
	}

	# Always format with a dot, regardless of the system language
	$latArg = $lat.ToString('0.########', $invariant)
	$lonArg = $lon.ToString('0.########', $invariant)
	$latRef = if ($lat -ge 0) { 'N' } else { 'S' }
	$lonRef = if ($lon -ge 0) { 'E' } else { 'W' }
	Write-Host "Coordinates: $latArg, $lonArg"

	$utcString = $selected.Date.Replace(' UTC', '')
	$utcTime = [datetime]::ParseExact($utcString, 'yyyy-MM-dd HH:mm:ss', $invariant, [System.Globalization.DateTimeStyles]::AssumeUniversal)
	$datetime = $utcTime.ToString('yyyy:MM:dd HH:mm:ss')

	Copy-Item -Path $file.FullName -Destination $targetFile -Force

	$exifOutput = & $exiftool -overwrite_original "-GPSLatitude#=$latArg" "-GPSLatitudeRef=$latRef" "-GPSLongitude#=$lonArg" "-GPSLongitudeRef=$lonRef" "-DateTimeOriginal=$datetime" "-CreateDate=$datetime" "-ModifyDate=$datetime" "-FileModifyDate=$datetime" "-FileCreateDate=$datetime" "$targetFile" 2>&1

	$check = @(& $exiftool -s3 -n -GPSLatitude -GPSLongitude "$targetFile" 2>$null)
	$verified = $false

	if ($check.Count -eq 2) {
		try {
			$writtenLat = [double]::Parse($check[0], $invariant)
			$writtenLon = [double]::Parse($check[1], $invariant)
			$verified = ([math]::Abs($writtenLat - $lat) -lt 0.00001) -and ([math]::Abs($writtenLon - $lon) -lt 0.00001)
		} catch {}
	}

	if ($verified) {
		Write-Host 'Geotagging completed:' $targetFile
	} else {
		Write-Host 'ERROR: Coordinates were not written correctly.'
		Write-Host '  Expected:' $latArg $lonArg
		Write-Host '  Read back:' ($check -join ' / ')
		if ($exifOutput) {
			Write-Host '  exiftool:' ($exifOutput -join ' | ')
		}
		[console]::beep(200, 500)
	}
}

[console]::beep(500, 200)
