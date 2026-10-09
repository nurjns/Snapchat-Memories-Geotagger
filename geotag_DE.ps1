<#
Version 1.1.0 - 09.10.2026 - @nurjns
#>

# Pfade
$sourceFolder = 'memories'
$targetFolder = 'memories_geotagged'
$jsonFile = 'json\memories_history.json'
$exiftool = '.\exiftool.exe'

# Maximale Abweichung in Sekunden fuer die automatische Zuordnung
$toleranceSeconds = 5

$invariant = [System.Globalization.CultureInfo]::InvariantCulture

# Ordner erstellen, falls nicht vorhanden
if (-not (Test-Path $targetFolder)) {
	New-Item -ItemType Directory -Path $targetFolder | Out-Null
	Write-Host "Zielordner wurde erstellt: $targetFolder"
}

# JSON laden mit UTF8-Encoding
$jsonRaw = Get-Content $jsonFile -Raw -Encoding utf8
$json = $jsonRaw | ConvertFrom-Json
$history = $json.'Saved Media' | Where-Object { $_.'Media Type' -eq 'Image' }

# Alle JPG- und PNG-Dateien laden (ohne -overlay)
$files = Get-ChildItem -Path $sourceFolder | Where-Object {
	$_.Extension -match '^\.(jpg|png)$' -and $_.BaseName -notmatch '-overlay'
}

# Startpunkt-Abfrage (Dateiname oder Datum)
$startInput = Read-Host 'Falls du ab einer bestimmten Datei oder einem Datum (YYYY-MM-DD) weitermachen willst, gib es ein (oder Enter fuer Start ab Anfang)'
$startFound = [string]::IsNullOrWhiteSpace($startInput)
$startAtFile = ''

if (-not $startFound) {
	if ($startInput -match '^\d{4}-\d{2}-\d{2}$') {
		$match = $files | Where-Object { $_.BaseName -like "$startInput*" } | Select-Object -First 1
		if ($match) {
			$startAtFile = $match.Name
			Write-Host 'Beginne ab erster Datei mit Datum' $startInput ':' $startAtFile
		} else {
			Write-Host 'Keine Datei mit Datum' $startInput 'gefunden. Starte von vorne.'
			$startFound = $true
		}
	} else {
		if ($files.Name -contains $startInput) {
			$startAtFile = $startInput
		} else {
			Write-Host "Datei '$startInput' wurde im Quellordner nicht gefunden. Starte von vorne."
			$startFound = $true
		}
	}
}

# Verarbeitung starten
foreach ($file in $files) {
	if (-not $startFound) {
		if ($file.Name -eq $startAtFile) {
			$startFound = $true
		} else {
			continue
		}
	}

	Write-Host "`n-> Verarbeite Datei: $($file.Name)"

	$targetFile = Join-Path $targetFolder ($file.BaseName + '_geotagged.jpg')
	if (Test-Path $targetFile) {
		Write-Host "WARNUNG: $($file.Name) wurde bereits verarbeitet. Ueberspringe."
		continue
	}

	$datePart = $file.BaseName -split '_' | Select-Object -First 1
	if (-not ($datePart -match '^\d{4}-\d{2}-\d{2}$')) {
		Write-Host "FEHLER: Ungueliges Datumsformat im Dateinamen: $($file.Name)"
		continue
	}

	$matchingEntries = @($history | Where-Object { ($_.Date -split ' ')[0] -eq $datePart })
	if ($matchingEntries.Count -eq 0) {
		Write-Host "FEHLER: Keine Eintraege fuer $($file.Name) gefunden."
		continue
	}

	# Zeitstempel-Kandidaten der Datei
	$fileTimes = @(
		$file.LastWriteTime
		$file.LastWriteTimeUtc
		$file.CreationTime
		$file.CreationTimeUtc
	)

	# Automatische Zuordnung ueber den Zeitstempel
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
		Write-Host ('Automatischer Treffer (' + [math]::Round($bestDiff, 1) + 's Abweichung):') $selected.Location '-' $selected.Date
	} else {
		$photoProcess = Start-Process -FilePath $file.FullName -PassThru

		if ($matchingEntries.Count -gt 1) {
			Write-Host "Kein automatischer Treffer. Mehrere Eintraege fuer $datePart gefunden:"
			for ($i = 0; $i -lt $matchingEntries.Count; $i++) {
				Write-Host ($i + 1) ':' $matchingEntries[$i].Location '-' $matchingEntries[$i].Date
			}
			$choice = Read-Host 'Nummer auswaehlen oder (s)kip'

			try {
				Start-Sleep -Seconds 1
				$photoProcess.CloseMainWindow() | Out-Null
				Start-Sleep -Seconds 1
				if (-not $photoProcess.HasExited) { $photoProcess.Kill() }
			} catch {}

			if ($choice -eq 's') {
				Write-Host 'Uebersprungen.'
				if (Test-Path $targetFile) {
					Remove-Item -Path $targetFile -Force
				}
				continue
			}

			if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchingEntries.Count) {
				$selected = $matchingEntries[[int]$choice - 1]
			} else {
				Write-Host 'Ungueltige Eingabe. Ueberspringe.'
				continue
			}
		} else {
			$selected = $matchingEntries[0]
			Write-Host 'Eintrag gefunden:' $selected.Location '-' $selected.Date
			$confirm = Read-Host 'Verwenden? (y/n)'

			try {
				Start-Sleep -Seconds 1
				$photoProcess.CloseMainWindow() | Out-Null
				Start-Sleep -Seconds 1
				if (-not $photoProcess.HasExited) { $photoProcess.Kill() }
			} catch {}

			if ($confirm.ToLower() -ne 'y') {
				Write-Host 'Foto uebersprungen.'
				continue
			}
		}
	}

	# Koordinaten aus dem Location-Feld holen (die beiden Zahlen am Ende)
	if ($selected.Location -notmatch '(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$') {
		Write-Host 'FEHLER: Standortangabe nicht lesbar:' $selected.Location
		continue
	}

	$lat = [math]::Round([double]::Parse($matches[1], $invariant), 6)
	$lon = [math]::Round([double]::Parse($matches[2], $invariant), 6)

	if ($lat -lt -90 -or $lat -gt 90 -or $lon -lt -180 -or $lon -gt 180) {
		Write-Host "FEHLER: Koordinaten ausserhalb des gueltigen Bereichs: $lat, $lon"
		continue
	}

	# Immer mit Punkt formatieren, unabhaengig von der Systemsprache
	$latArg = $lat.ToString('0.########', $invariant)
	$lonArg = $lon.ToString('0.########', $invariant)
	$latRef = if ($lat -ge 0) { 'N' } else { 'S' }
	$lonRef = if ($lon -ge 0) { 'E' } else { 'W' }
	Write-Host "Koordinaten: $latArg, $lonArg"

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
		Write-Host 'Geotagging abgeschlossen:' $targetFile
	} else {
		Write-Host 'FEHLER: Koordinaten wurden nicht korrekt geschrieben.'
		Write-Host '  Erwartet:' $latArg $lonArg
		Write-Host '  Gelesen: ' ($check -join ' / ')
		if ($exifOutput) {
			Write-Host '  exiftool:' ($exifOutput -join ' | ')
		}
		[console]::beep(200, 500)
	}
}

[console]::beep(500, 200)
