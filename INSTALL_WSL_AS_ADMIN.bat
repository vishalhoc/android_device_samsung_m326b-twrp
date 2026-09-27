@echo off
:: WSL2 + Ubuntu 22.04 Setup for TWRP Build
:: Run this as Administrator

echo =====================================================
echo  WSL2 + Ubuntu 22.04 - TWRP Build Environment Setup
echo =====================================================
echo.

:: Enable WSL features
echo [1/4] Enabling Windows Subsystem for Linux...
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul 2>&1
echo Done.

echo [2/4] Enabling Virtual Machine Platform...
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul 2>&1
echo Done.

echo [3/4] Setting WSL2 as default...
wsl --set-default-version 2 >nul 2>&1

echo [4/4] Installing Ubuntu 22.04...
wsl --install -d Ubuntu-22.04

echo.
echo =====================================================
echo  IMPORTANT: After Ubuntu finishes installing,
echo  set up your Ubuntu username + password when prompted.
echo  Then run the TWRP build script inside Ubuntu.
echo =====================================================
echo.
pause
