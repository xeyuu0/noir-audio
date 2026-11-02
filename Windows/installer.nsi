Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
Name "NOIR Audio"
OutFile "../dist/NOIR-Audio-0.1.0-Windows-x64-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\NOIR Audio"
InstallDirRegKey HKCU "Software\NOIR Audio" "InstallPath"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ABORTWARNING
!define MUI_ICON "resources/Noir.ico"
!define MUI_UNICON "resources/Noir.ico"
!define MUI_WELCOMEPAGE_TITLE "NOIR Audio for Windows"
!define MUI_WELCOMEPAGE_TEXT "Install the native Windows audio studio for your account.$\r$\n$\r$\nThis is an unsigned development preview. Windows virtual audio drivers and FFmpeg are separate optional installations.$\r$\n$\r$\nYour recordings and sessions are kept in Local AppData and survive uninstall."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "../LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\NOIR Audio.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
Function .onInit
  FindWindow $0 "NOIRStudio"
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONINFORMATION "Close NOIR Audio before installing this update."
    Abort
  ${EndIf}
FunctionEnd
Section "NOIR Audio"
  SetOutPath "$INSTDIR"
  File "../dist/NOIR-Audio-Windows/NOIR Audio.exe"
  File "../dist/NOIR-Audio-Windows/README.md"
  File "../dist/NOIR-Audio-Windows/LICENSE.txt"
  File "../dist/NOIR-Audio-Windows/OctopusEAX-LICENSE.txt"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\NOIR Audio"
  CreateShortcut "$SMPROGRAMS\NOIR Audio\NOIR Audio.lnk" "$INSTDIR\NOIR Audio.exe"
  CreateShortcut "$SMPROGRAMS\NOIR Audio\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\NOIR Audio" "InstallPath" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "DisplayName" "NOIR Audio"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "DisplayIcon" "$INSTDIR\NOIR Audio.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "DisplayVersion" "0.1.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "URLInfoAbout" "https://noir-audio-orpin.vercel.app"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio" "NoRepair" 1
SectionEnd
Section "Uninstall"
  FindWindow $0 "NOIRStudio"
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONINFORMATION "Close NOIR Audio before uninstalling."
    Abort
  ${EndIf}
  Delete "$INSTDIR\NOIR Audio.exe"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\OctopusEAX-LICENSE.txt"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$SMPROGRAMS\NOIR Audio\NOIR Audio.lnk"
  Delete "$SMPROGRAMS\NOIR Audio\Uninstall.lnk"
  RMDir "$SMPROGRAMS\NOIR Audio"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOIR Audio"
  DeleteRegKey HKCU "Software\NOIR Audio"
SectionEnd
