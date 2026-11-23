# SINTONÍA — arma el instalador de Windows (corre ADENTRO de la máquina virtual de Windows).
#   powershell -ExecutionPolicy Bypass -File herramientas_windows.ps1
# Deja dist\Sintonia-Instalador.exe
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
Set-Location $PSScriptRoot
$herr = "C:\herramientas"; New-Item -ItemType Directory -Force $herr | Out-Null

# 1. Python
$py = "C:\Program Files\Python312\python.exe"
if (-not (Test-Path $py)) {
  Invoke-WebRequest https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe -OutFile "$herr\python.exe"
  Start-Process "$herr\python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
}
$venv = "C:\venv"
if (-not (Test-Path "$venv\Scripts\python.exe")) { & $py -m venv $venv }
$vpy = "$venv\Scripts\python.exe"
& $vpy -m pip install -q --upgrade pip
& $vpy -m pip install -q --timeout 120 --retries 10 -r requirements.txt pyinstaller py7zr

# 2. libmpv (compilación automática de mpv para Windows; se descomprime con 7-Zip: py7zr no puede con este .7z)
if (-not (Test-Path "libmpv-2.dll") -or (Get-Item "libmpv-2.dll").Length -lt 1MB) {
  $rel = Invoke-RestMethod https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest
  $a = $rel.assets | Where-Object { $_.name -like "mpv-dev-x86_64-2*.7z" } | Select-Object -First 1
  Invoke-WebRequest $a.browser_download_url -OutFile "$herr\mpv-dev.7z"
  Invoke-WebRequest https://www.7-zip.org/a/7zr.exe -OutFile "$herr\7zr.exe"
  & "$herr\7zr.exe" e -y "-o$herr\mpv" "$herr\mpv-dev.7z" libmpv-2.dll | Out-Null
  Copy-Item "$herr\mpv\libmpv-2.dll" . -Force
  if ((Get-Item "libmpv-2.dll").Length -lt 1MB) { throw "libmpv-2.dll vacía" }
}

# 2b. vulkan-1.dll (la necesita libmpv; las PCs sin drivers de video, como esta VM, no la tienen)
if (-not (Test-Path "vulkan-1.dll")) {
  if (-not (Test-Path "$herr\vulkanrt")) {   # ya bajado de antes: no depender del enlace de LunarG
    Invoke-WebRequest https://sdk.lunarg.com/sdk/download/1.4.328.1/windows/VulkanRT-X64-1.4.328.1-Components.zip -OutFile "$herr\vulkanrt.zip"
    Expand-Archive "$herr\vulkanrt.zip" -DestinationPath "$herr\vulkanrt" -Force
  }
  Get-ChildItem -Recurse "$herr\vulkanrt" -Filter vulkan-1.dll | Where-Object { $_.FullName -match "x64" } | Select-Object -First 1 | Copy-Item -Destination .
}

# 3. Shaders
Get-ChildItem sintonia\shaders\*.frag | ForEach-Object { & "$venv\Scripts\pyside6-qsb.exe" --qt6 -o "$($_.FullName).qsb" $_.FullName }

# 4. La app
& "$venv\Scripts\pyinstaller.exe" --noconfirm --log-level WARN sintonia.spec

# 5. El instalador (Inno Setup: la última versión, de GitHub)
function Buscar-Iscc { Get-ChildItem "$env:ProgramFiles\Inno Setup*\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup*\ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
$iscc = Buscar-Iscc
if (-not $iscc) {
  $rel = Invoke-RestMethod https://api.github.com/repos/jrsoftware/issrc/releases/latest
  $a = $rel.assets | Where-Object { $_.name -like "innosetup-*-x64.exe" } | Select-Object -First 1
  Invoke-WebRequest $a.browser_download_url -OutFile "$herr\innosetup.exe"
  Start-Process "$herr\innosetup.exe" -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS" -Wait
  $iscc = Buscar-Iscc
}
& $iscc /Q empaque\sintonia.iss
Get-Item dist\Sintonia-Instalador.exe | Select-Object Name, Length
