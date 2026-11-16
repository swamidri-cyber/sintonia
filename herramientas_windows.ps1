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

# 2. libmpv (compilación automática de mpv para Windows)
if (-not (Test-Path "libmpv-2.dll")) {
  $rel = Invoke-RestMethod https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest
  $a = $rel.assets | Where-Object { $_.name -like "mpv-dev-x86_64-2*.7z" } | Select-Object -First 1
  Invoke-WebRequest $a.browser_download_url -OutFile "$herr\mpv-dev.7z"
  & $vpy -c "import py7zr; py7zr.SevenZipFile(r'$herr\mpv-dev.7z').extract(path=r'$herr\mpv', targets=['libmpv-2.dll'])"
  Copy-Item "$herr\mpv\libmpv-2.dll" .
}

# 3. Shaders
Get-ChildItem sintonia\shaders\*.frag | ForEach-Object { & "$venv\Scripts\pyside6-qsb.exe" --qt6 -o "$($_.FullName).qsb" $_.FullName }

# 4. La app
& "$venv\Scripts\pyinstaller.exe" --noconfirm --log-level WARN sintonia.spec

# 5. El instalador
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  Invoke-WebRequest https://files.jrsoftware.org/is/6/innosetup-6.7.4.exe -OutFile "$herr\innosetup.exe"
  Start-Process "$herr\innosetup.exe" -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
}
& $iscc /Q empaque\sintonia.iss
Get-Item dist\Sintonia-Instalador.exe | Select-Object Name, Length
