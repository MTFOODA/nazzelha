@echo off
setlocal
pushd "%~dp0"
if not exist "build\windows_controls\runner\Debug\nazzelha.exe" (
  echo Build the Windows application first. See docs\DOWNLOADS_AND_DESIGN.md.
  pause
  popd
  exit /b 1
)
start "" /D "%~dp0" "%~dp0build\windows_controls\runner\Debug\nazzelha.exe"
popd
