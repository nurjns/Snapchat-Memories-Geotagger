# Snapchat Memories Geotagger

A PowerShell script to automatically restore missing GPS coordinates in downloaded Snapchat Memories. 

## The Problem
Downloaded Snapchat Memories do not contain any embedded EXIF location metadata. As a result, gallery applications (such as Google Photos or Apple Photos) cannot display where the photos were taken. 

This script extracts recorded location data from your Snapchat JSON export and injects precise EXIF GPS coordinates and timestamps directly into the image files - provided the memory carries location data in the export.

Coordinates are read straight from the export. Each image is matched to its location entry automatically by comparing the file timestamp against the entry time (±5 s, configurable); only if no match is found does the script open the photo and ask you to pick an entry manually. Every write is verified by reading the GPS tags back out of the file, so a success message means the coordinates are really there.

---

## Prerequisites
* **Venue Lens Usage:** Snaps must have been captured using a Location/Venue Lens for Snapchat to log the place in `memories_history.json`.
* **Snapchat Memories & JSON Export:** Requires `json/memories_history.json` and your downloaded photo files in the `memories/` directory.
* **[ExifTool](https://exiftool.org/)** — Download the Windows executable zip, extract it, rename `exiftool(-k).exe` to `exiftool.exe`, and place it in the script directory.
* **PowerShell 5.1+** (Pre-installed on Windows 11).

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
│   ├── 2026-10-09_abc123-main.jpg
│   └── ...
├── 📁 json/
│   └── memories_history.json      # Extracted from your Snapchat Data Export
├── 📁 exiftool_files/                    # ExifTool helper files
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

## Disclaimer
This project is an independent open-source tool and is not affiliated, associated, authorized, endorsed by, or in any way officially connected with Snap Inc. or Snapchat.
