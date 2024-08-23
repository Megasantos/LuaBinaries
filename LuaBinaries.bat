@echo off
set "scriptPath=%~dp0LuaBinaries.ps1"
start powershell -noexit -ExecutionPolicy Bypass -File "%scriptPath%"
