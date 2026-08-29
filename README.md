# Snapchat Memories Geotagger

A PowerShell script to automatically restore missing GPS coordinates in downloaded Snapchat Memories. 

## The Problem
Downloaded Snapchat Memories do not contain any embedded EXIF location metadata. As a result, gallery applications (such as Immich, Google Photos, or Apple Photos) cannot display where the photos were taken. 

This script extracts recorded location history from your Snapchat JSON export and uses a geocoding API to inject precise EXIF GPS coordinates and timestamps back into the image files—provided you used a **Location / Venue Lens** when taking the snap.

---

## Prerequisites
* **Venue Lens Usage:** Snaps must have been captured using a Location/Venue Lens for Snapchat to log the place in `snap_map_places_history.json`.
* **Snapchat Memories & JSON Export:** Requires `json/snap_map_places_history.json` and your downloaded photo files in the `memories/` directory.
* **[ExifTool](https://exiftool.org/)** — Download the Windows executable zip, extract it, rename `exiftool(-k).exe` to `exiftool.exe`, and place it in the script directory.
* **PowerShell 5.1+** (Pre-installed on Windows 10/11).

## How to Export Your Snapchat Data

1. Open Snapchat and go to **Settings** -> **My Data**.
2. Under **Select Data**, make sure to enable:
   * **Export your Memories**
   * **Export JSON files**
3. Set the date range to **"All time"**.
4. Submit the request and download the export ZIP once Snapchat notifies you by mail.

---

## Folder Structure
Organize your project directory as follows before running the script:

```text
📁 ProjectFolder/
├── 📁 memories/                          # Input folder containing downloaded photos
│   ├── 2026-08-29_abc123-main.jpg
│   └── ...
├── 📁 json/
│   └── snap_map_places_history.json      # Extracted from your Snapchat Data Export
├── 📄 exiftool.exe                       # ExifTool executable
└── 📄 geotag.ps1                         # This script
```

## How to Use

1. Open PowerShell and navigate to your project directory:
   ```powershell
   cd X:\Path\To\ProjectFolder
2. Set the execution policy for the current session:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
3. Run the script:
   ```powershell
   .\geotag.ps1
