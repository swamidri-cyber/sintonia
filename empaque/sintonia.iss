; SINTONÍA — instalador de Windows (Inno Setup 6)
;   iscc empaque\sintonia.iss   →  dist\Sintonia-Instalador.exe
; Se instala para el usuario (sin pedir permisos de administrador).
#define Nombre "Sintonía"
#define Version "1.0.0"

[Setup]
AppId={{6F4B3C1A-5D2E-4A7B-9C8D-51A7710E0A11}
AppName={#Nombre}
AppVersion={#Version}
AppPublisher=Sintonía
DefaultDirName={localappdata}\Programs\Sintonia
DefaultGroupName={#Nombre}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Sintonia-Instalador
SetupIconFile=..\sintonia\icono.ico
UninstallDisplayIcon={app}\Sintonia.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "..\dist\Sintonia\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#Nombre}"; Filename: "{app}\Sintonia.exe"
Name: "{userdesktop}\{#Nombre}"; Filename: "{app}\Sintonia.exe"; Tasks: escritorio

[Run]
Filename: "{app}\Sintonia.exe"; Description: "Abrir {#Nombre}"; Flags: nowait postinstall skipifsilent
