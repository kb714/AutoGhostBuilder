param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

$MOD_NAME = "AutoGhostBuilder"
$BUILD_DIR = "${MOD_NAME}_${Version}"
$ZIP_NAME = "${BUILD_DIR}.zip"

Write-Host "Building release for $MOD_NAME version $Version" -ForegroundColor Cyan

# Update version in info.json
Write-Host "Updating info.json..." -ForegroundColor Yellow
$infoJson = Get-Content "info.json" -Raw | ConvertFrom-Json
$infoJson.version = $Version
$infoJson | ConvertTo-Json -Depth 10 | Set-Content "info.json"

# Update version in package.json
if (Test-Path "package.json") {
    Write-Host "Updating package.json..." -ForegroundColor Yellow
    $packageJson = Get-Content "package.json" -Raw | ConvertFrom-Json
    $packageJson.version = $Version
    $packageJson | ConvertTo-Json -Depth 10 | Set-Content "package.json"
}

# Clean previous build
Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
if (Test-Path $BUILD_DIR) {
    Remove-Item -Recurse -Force $BUILD_DIR
}
if (Test-Path $ZIP_NAME) {
    Remove-Item -Force $ZIP_NAME
}

# Create build directory
Write-Host "Creating build directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null

# Copy mod files
Write-Host "Copying mod files..." -ForegroundColor Yellow
Copy-Item "info.json" "$BUILD_DIR\"
Copy-Item "control.lua" "$BUILD_DIR\"
Copy-Item "data.lua" "$BUILD_DIR\"
Copy-Item "changelog.txt" "$BUILD_DIR\"
Copy-Item -Recurse "locale" "$BUILD_DIR\"
Copy-Item -Recurse "graphics" "$BUILD_DIR\"
Copy-Item -Recurse "src" "$BUILD_DIR\"

# Remove test files from src
Write-Host "Removing test files..." -ForegroundColor Yellow
if (Test-Path "$BUILD_DIR\src\tests") {
    Remove-Item -Recurse -Force "$BUILD_DIR\src\tests"
}

# Create zip file
Write-Host "Creating $ZIP_NAME..." -ForegroundColor Yellow
Compress-Archive -Path $BUILD_DIR -DestinationPath $ZIP_NAME -Force

# Clean up build directory
Write-Host "Cleaning up..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $BUILD_DIR

Write-Host ""
Write-Host "✅ Release $ZIP_NAME created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Test the mod by extracting $ZIP_NAME to your Factorio mods folder"
Write-Host "2. Upload to https://mods.factorio.com"
