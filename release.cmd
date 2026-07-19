@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release.ps1" %*
