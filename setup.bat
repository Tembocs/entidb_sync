@echo off
REM EntiDB Sync - Development Setup Script for Windows
REM Checks prerequisites and installs dependencies for all packages

echo EntiDB Sync - Development Setup
echo ================================
echo.

REM Check Dart SDK version
echo Checking Dart SDK version...
dart --version >nul 2>&1
if errorlevel 1 (
    echo X Dart SDK not found. Please install from https://dart.dev/get-dart
    exit /b 1
)

for /f "tokens=3" %%v in ('dart --version 2^>^&1 ^| findstr /C:"Dart SDK version"') do set DART_VERSION=%%v
echo √ Found Dart SDK %DART_VERSION%

echo.
echo Installing dependencies...
echo.

REM Install protocol package
echo . entidb_sync_protocol
cd packages\entidb_sync_protocol
call dart pub get
cd ..\..

REM Install client package
echo . entidb_sync_client
cd packages\entidb_sync_client
call dart pub get
cd ..\..

REM Install server package
echo . entidb_sync_server
cd packages\entidb_sync_server
call dart pub get
cd ..\..

echo.
echo √ Setup complete!
echo.
echo Next steps:
echo   * Review documentation: doc\architecture.md
echo   * Run tests: dart test packages\^<package^>\test
echo   * Start development: see CONTRIBUTING.md
