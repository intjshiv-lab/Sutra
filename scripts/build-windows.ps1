# ==============================================================================
# Sutra Windows 1-Click Native AOT Builder
# Run this PowerShell script on any Windows machine (with .NET 9 SDK)
# ==============================================================================

Write-Host "🪡 Sutra Windows Native AOT Builder" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────────────"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$WindowsAppDir = Join-Path $ProjectRoot "apps\sutra-windows"
$FfiDir = Join-Path $ProjectRoot "crates\sutra-ffi"
$DistDir = Join-Path $ProjectRoot "dist"

# 1. Build Rust FFI DLL
Write-Host "📦 Compiling Rust FFI DLL (sutra_ffi.dll)..." -ForegroundColor Yellow
Push-Location $FfiDir
cargo build --release
Pop-Location

# 2. Build WinUI 3 Native AOT .exe
Write-Host "⚙️ Compiling WinUI 3 Native AOT Standalone .exe..." -ForegroundColor Yellow
Push-Location $WindowsAppDir
dotnet publish -c Release -r win-x64 /p:PublishAot=true /p:WindowsPackageType=None -o "$DistDir\windows"
Pop-Location

Write-Host "──────────────────────────────────────────────"
Write-Host "✅ Standalone Windows executable built successfully!" -ForegroundColor Green
Write-Host "📍 Location: $DistDir\windows\SutraWindows.exe"
Write-Host "⚖️  Zero runtime dependencies (Native AOT machine code)"
