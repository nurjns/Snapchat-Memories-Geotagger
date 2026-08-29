<#
Version 1.0 - 29.08.2026 - @nurjns
#>

# Pfade
$sourceFolder = 'memories'
$targetFolder = 'memories_geotagged'
$jsonFile = 'json\snap_map_places_history.json'
$exiftool = '.\exiftool.exe'

# Ordner erstellen, falls nicht vorhanden
if (-not (Test-Path $targetFolder)) {
	New-Item -ItemType Directory -Path $targetFolder | Out-Null
	Write-Host "📁 Zielordner wurde erstellt: $targetFolder"
}

# Funktion für Umlaut-Konvertierung
function ConvertUmlautsAndUrlEncode {
	param([string]$str)
	
	# Komma entfernen
	$str = $str -replace ',', ''

	# Umlaute ersetzen
	$str = $str -replace 'ü', 'ue'
	$str = $str -replace 'Ü', 'Ue'
	$str = $str -replace 'ä', 'ae'
	$str = $str -replace 'Ä', 'Ae'
	$str = $str -replace 'ö', 'oe'
	$str = $str -replace 'Ö', 'Oe'
	$str = $str -replace 'ß', 'ss'

	# Leerzeichen zu %20 (keine weitere URL-Kodierung)
	return $str -replace ' ', '%20'
}

# JSON laden mit UTF8-Encoding
$jsonRaw = Get-Content $jsonFile -Raw -Encoding utf8
$json = $jsonRaw | ConvertFrom-Json
$history = $json.'Snap Map Places History'

# Alle JPG- und PNG-Dateien laden (ohne -overlay)
$files = Get-ChildItem -Path $sourceFolder | Where-Object {
	$_.Extension -match '^\.(jpg|png)$' -and $_.BaseName -notmatch '-overlay'
}

# Startpunkt-Abfrage (Dateiname oder Datum)
$startInput = Read-Host '🔁 Falls du ab einer bestimmten Datei oder einem Datum (YYYY-MM-DD) weitermachen willst, gib es ein (oder Enter für Start ab Anfang)'
$startFound = [string]::IsNullOrWhiteSpace($startInput)
$startAtFile = ''

if (-not $startFound) {
	if ($startInput -match '^\d{4}-\d{2}-\d{2}$') {
		# Start per Datum
		$match = $files | Where-Object { $_.BaseName -like "$startInput*" } | Select-Object -First 1
		if ($match) {
			$startAtFile = $match.Name
			Write-Host '📆 Beginne ab erster Datei mit Datum' $startInput ':' $startAtFile
		} else {
			Write-Host '❗️Keine Datei mit Datum' $startInput 'gefunden. Starte trotzdem ganz normal.'
			$startFound = $true
		}
	} else {
		# Start per Dateiname
		if ($files.Name -contains $startInput) {
			$startAtFile = $startInput
		} else {
			Write-Host "❗️Datei '$startInput' wurde im Quellordner nicht gefunden. Starte trotzdem ganz normal."
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

	Write-Host "`n➡️ Verarbeite Datei: $($file.Name)"

	# Ziel-Datei prüfen
	$targetFile = Join-Path $targetFolder ($file.BaseName + '_geotagged.jpg')
	if (Test-Path $targetFile) {
		Write-Host "⚠️  $($file.Name) wurde bereits verarbeitet. Überspringe."
		continue
	}

	# Datum aus Dateiname extrahieren
	$datePart = $file.BaseName -split '_' | Select-Object -First 1
	if (-not ($datePart -match '^\d{4}-\d{2}-\d{2}$')) {
		Write-Host "❌ Ungültiges Datumsformat im Dateinamen: $($file.Name)"
		continue
	}

	# Einträge für Datum filtern
	$matchingEntries = $history | Where-Object { ($_.Date -split ' ')[0] -eq $datePart }
	if ($matchingEntries.Count -eq 0) {
		Write-Host "❌ Keine Einträge für $($file.Name) gefunden."
		continue
	}

	# Foto öffnen (Standardprogramm)
	$photoProcess = Start-Process -FilePath $file.FullName -PassThru

	if ($matchingEntries.Count -gt 1) {
		Write-Host "📅 Mehrere Einträge für $datePart gefunden"
		for ($i = 0; $i -lt $matchingEntries.Count; $i++) {
			$entry = $matchingEntries[$i]
			Write-Host ($i+1) ':' $entry.Place '–' $entry.'Place Location' '–' $entry.Date
		}
		$choice = Read-Host '❓ Nummer auswählen oder (s)kip'

		# Foto schließen
		try {
			Start-Sleep -Seconds 1
			$photoProcess.CloseMainWindow() | Out-Null
			Start-Sleep -Seconds 1
			if (!$photoProcess.HasExited) { $photoProcess.Kill() }
		} catch {}

		if ($choice -eq 's') {
			Write-Host '⏩ Übersprungen.'
			if (Test-Path $targetFile) {
				Remove-Item -Path $targetFile -Force
				Write-Host "🗑️ Vorhandene Datei $targetFile gelöscht."
			}
			continue
		}

	if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $matchingEntries.Count) {
		$selected = $matchingEntries[[int]$choice - 1]
	} else {
		Write-Host '❌ Ungültige Eingabe. Überspringe.'
		continue
	}
	} else {
		$selected = $matchingEntries[0]
		Write-Host '📍 Eintrag gefunden:' $selected.Place '–' $selected.'Place Location'
		$confirm = Read-Host '✅ Verwenden? (y/n)'

		# Foto schließen
		try {
			Start-Sleep -Seconds 1
			$photoProcess.CloseMainWindow() | Out-Null
			Start-Sleep -Seconds 1
			if (!$photoProcess.HasExited) { $photoProcess.Kill() }
		} catch {}

		if ($confirm.ToLower() -ne 'y') {
			Write-Host '⏩ Foto übersprungen.'
			continue
		}
	}

	# API-Abfrage vorbereiten
	$placeQuery = "$($selected.Place) $($selected.'Place Location')"
	$encodedQuery = ConvertUmlautsAndUrlEncode $placeQuery
	$apiUrl = 'https://photon.komoot.io/api/?q=' + $encodedQuery

	Write-Host '🔗 API-URL:' $apiUrl

	try {
		$response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
		if ($response.features.Count -eq 0) {
			Write-Host '❌ Keine Koordinaten gefunden.'
			continue
		}
		$coords = $response.features[0].geometry.coordinates
		$lon = [math]::Round($coords[0], 3)
		$lat = [math]::Round($coords[1], 3)
		Write-Host "🌍 Gefundene Koordinaten: $lat, $lon"
	} catch {
		Write-Host '❌ Fehler bei API-Anfrage:' $_
		continue
	}

	# Datum mit Uhrzeit aus JSON-Eintrag übernehmen und UTC+2 korrigieren
	$utcString = $selected.Date.Replace(' UTC','')
	$utcTime = [datetime]::ParseExact($utcString, 'yyyy-MM-dd HH:mm:ss', $null, [System.Globalization.DateTimeStyles]::AssumeUniversal)
	$datetime = $utcTime.ToString('yyyy:MM:dd HH:mm:ss')

	# Datei in Zielordner kopieren
	Copy-Item -Path $file.FullName -Destination $targetFile -Force

	# ExifTool-Befehl auf kopierte Datei
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
		Write-Host '✅ Geotagging abgeschlossen:' $targetFile
	} else {
		Write-Host '❌ Fehler beim Schreiben der Metadaten.'
	}
}

[console]::beep(500,200)