@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem  FACEIT Anticheat Helper

set "APP_VER=1.0"
set "APP_URL=https://github.com/kazxk/faceit-helper"
title FACEIT Anticheat Helper

if defined PROCESSOR_ARCHITEW6432 (
    if exist "%SystemRoot%\Sysnative\cmd.exe" (
        "%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
        exit /b !errorlevel!
    )
)

set "SYSDIR=%SystemRoot%\System32"
set "PATH=%SYSDIR%;%SYSDIR%\WindowsPowerShell\v1.0;%PATH%"

set "IS_ADMIN=0"
reg query "HKU\S-1-5-19" >nul 2>&1 && set "IS_ADMIN=1"

if "%IS_ADMIN%"=="0" (
    if /i "%~1"=="/elevated" goto :no_admin
    call :elevate
    exit /b
)

call :init
call :splash


:menu
set "MENU_MISSES=0"
:menu_draw
cls
call :banner
echo.
echo   Reads your machine, tells you exactly why FACEIT Anti-Cheat
echo   would refuse to start, and fixes what Windows lets it fix.
echo.
echo    %BLD%[1]%CLR%  Scan only          %DIM%report, change nothing%CLR%
echo    %BLD%[2]%CLR%  Scan and fix       %DIM%report, then ask about each item%CLR%
echo    %BLD%[3]%CLR%  Open the log file
echo    %BLD%[4]%CLR%  Exit
echo.
echo(  %DIM%Log: !LOGFILE!%CLR%
echo.
set "CH="
set /p "CH=  Choose [1-4]: "
if "!CH!"=="1" goto :run_scan_only
if "!CH!"=="2" goto :run_scan_fix
if "!CH!"=="3" goto :open_log
if "!CH!"=="4" exit /b 0
set /a MENU_MISSES+=1
if %MENU_MISSES% GEQ 10 (
    echo.
    echo   No usable input. Run this from a console window.
    exit /b 1
)
goto :menu_draw

:open_log
if exist "%LOGFILE%" (
    start "" "%SystemRoot%\notepad.exe" "%LOGFILE%"
) else (
    echo.
    echo   No log yet - run a scan first.
    call :anykey
)
goto :menu


:run_scan_only
cls
call :banner
call :scan
call :summary
if %CNT_FIXABLE% GTR 0 (
    echo   %CNT_FIXABLE% item^(s^) can be fixed from Windows. Re-run and choose %BLD%[2]%CLR%.
    echo.
)
call :anykey
goto :menu


:run_scan_fix
cls
call :banner
call :scan
call :summary

set /a _todo=CNT_FIXABLE+CNT_OPTIONAL
if !_todo! EQU 0 (
    echo   Nothing here can be changed from inside Windows.
    echo.
    call :anykey
    goto :menu
)

call :rule
echo   %BLD%APPLYING FIXES%CLR%
call :rule
echo.
echo   !_todo! item^(s^) can be changed from Windows. You will be asked
echo   about each one. Answer %BLD%A%CLR% to accept the rest without asking.

for %%v in (APPLY_ALL REBOOT_NEEDED CNT_APPLIED CNT_FAILED) do set "%%v=0"

call :fix_all

echo.
call :rule
echo   %BLD%RESULT%CLR%
call :rule
echo.
echo     Applied  %GRN%%CNT_APPLIED%%CLR%
echo     Failed   %RED%%CNT_FAILED%%CLR%
echo.
call :log "FIX RESULT: applied=%CNT_APPLIED% failed=%CNT_FAILED%"

if "%REBOOT_NEEDED%"=="1" (
    echo   %YEL%A restart is required before any of this takes effect.%CLR%
    echo   %DIM%Boot configuration and VBS/HVCI are only read at boot time.%CLR%
    echo.
    call :ask "  Restart now?"
    if /i "!ANS!"=="Y" (
        call :log "User chose to restart."
        shutdown /r /t 10 /c "Restarting to apply FACEIT Anticheat Helper changes." >nul 2>&1
        set "RC=!errorlevel!"
        echo.
        if "!RC!"=="0" (
            echo   Restarting in 10 seconds. Type  shutdown /a  to cancel.
        ) else (
            echo   %RED%Windows refused to schedule the restart.%CLR% Restart manually.
        )
        call :anykey
        exit /b 0
    )
    echo.
    echo   Restart manually before launching FACEIT, then run this script
    echo   again with option %BLD%[1]%CLR% to confirm everything took effect.
) else (
    echo   Nothing was applied, so no restart is needed.
)
echo.
call :anykey
goto :menu


:scan
for %%v in (CNT_OK CNT_FAIL CNT_WARN CNT_FIXABLE CNT_OPTIONAL BIOS_WORK) do set "%%v=0"
for %%v in (LEGACY_BOOT BIOS_SECUREBOOT BIOS_TPM) do set "%%v="

for %%F in (TESTSIGNING NOINTEGRITY DEBUG FLIGHTSIGN LOADOPTIONS SAFEBOOT HYPERVISOR VBS HVCI BLOCKLIST POLICY) do set "NEED_%%F=0"

call :log ""
call :log "==================================================================="
call :log "Scan started %DATE% %TIME%   script v%APP_VER%"
call :log "==================================================================="

set "BCDFILE=%WORKDIR%\bcd.txt"
del /q "%BCDFILE%" >nul 2>&1
bcdedit /enum "{current}" > "%BCDFILE%" 2>nul
set "BCD_OK=1"
if not exist "%BCDFILE%" set "BCD_OK=0"
if "%BCD_OK%"=="1" for %%S in ("%BCDFILE%") do if %%~zS EQU 0 set "BCD_OK=0"

call :section "A.  SYSTEM"
call :scan_system

call :section "B.  FIRMWARE   (changed in BIOS/UEFI setup, not by any script)"
call :scan_firmware

call :section "C.  BOOT CONFIGURATION"
call :scan_boot

call :section "D.  WINDOWS SECURITY FEATURES"
call :scan_security

call :section "E.  RUNTIME STATE"
call :scan_runtime

call :section "F.  FACEIT ANTI-CHEAT"
call :scan_faceit
goto :eof


:scan_system
set "NTKEY=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

call :regval "%NTKEY%" "ProductName"
set "OS_NAME=!RV!"
call :regval "%NTKEY%" "CurrentBuild"
set "OS_BUILD=!RV!"
call :regval "%NTKEY%" "DisplayVersion"
set "OS_DISP=!RV!"

if not defined OS_BUILD set "OS_BUILD=0"
if not defined OS_NAME set "OS_NAME=Unknown Windows"

if !OS_BUILD! GEQ 22000 set "OS_NAME=!OS_NAME:Windows 10=Windows 11!"

set "OS_TEXT=!OS_NAME!"
if defined OS_DISP set "OS_TEXT=!OS_TEXT! !OS_DISP!"
set "OS_TEXT=!OS_TEXT!, build !OS_BUILD!"
call :row INFO "Windows version" "!OS_TEXT!"

if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    call :row OK "Architecture" "64-bit x64"
) else if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    call :row OK "Architecture" "64-bit ARM64"
) else (
    call :row FAIL "Architecture" "%PROCESSOR_ARCHITECTURE% - FACEIT AC needs 64-bit Windows"
)

if !OS_BUILD! GEQ 22000 (
    call :row OK "Supported build" "Windows 11 - supported"
) else if !OS_BUILD! GEQ 17763 (
    call :row OK "Supported build" "Windows 10 1809 or newer - supported"
) else if !OS_BUILD! GEQ 10240 (
    call :row WARN "Supported build" "Windows 10 older than 1809 - update Windows"
) else (
    call :row FAIL "Supported build" "older than Windows 10 - FACEIT AC will not run"
)

set "IS_UEFI=0"
if "%BCD_OK%"=="1" (
    findstr /i /c:"winload.efi" "%BCDFILE%" >nul 2>&1
    if not errorlevel 1 set "IS_UEFI=1"
)
if "!IS_UEFI!"=="0" (
    reg query "HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State" >nul 2>&1
    if not errorlevel 1 set "IS_UEFI=1"
)

if "!IS_UEFI!"=="1" (
    call :row OK "Firmware mode" "UEFI - disk is GPT, Secure Boot is possible"
) else (
    call :row FAIL "Firmware mode" "legacy BIOS/CSM - Secure Boot is impossible"
    set /a BIOS_WORK+=1
    set "LEGACY_BOOT=1"
)

set "BIOSKEY=HKLM\HARDWARE\DESCRIPTION\System\BIOS"
call :regval "%BIOSKEY%" "SystemManufacturer"
set "SYS_MFR=!RV!"
call :regval "%BIOSKEY%" "SystemProductName"
set "SYS_PRD=!RV!"

set "VM_HIT="
for %%V in (VMware VirtualBox innotek QEMU Parallels KVM Bochs "Virtual Machine" "Virtual Platform") do (
    call :contains "!SYS_MFR! !SYS_PRD!" "%%~V"
    if "!FOUND!"=="1" set "VM_HIT=%%~V"
)
if defined VM_HIT (
    call :row FAIL "Physical machine" "virtual machine detected - !VM_HIT! - FACEIT AC blocks VMs"
) else (
    set "HW_TEXT=!SYS_MFR! !SYS_PRD!"
    if "!HW_TEXT!"==" " set "HW_TEXT=hardware not reported"
    call :row OK "Physical machine" "!HW_TEXT!"
)
goto :eof


:scan_firmware
call :regval "HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State" "UEFISecureBootEnabled"
if "!RVERR!"=="1" (
    call :row FAIL "Secure Boot" "not reported - Windows is not booted in UEFI mode"
    set /a BIOS_WORK+=1
    set "BIOS_SECUREBOOT=1"
) else if /i "!RV!"=="0x1" (
    call :row OK "Secure Boot" "enabled"
) else (
    call :row FAIL "Secure Boot" "DISABLED - required by FACEIT AC"
    set /a BIOS_WORK+=1
    set "BIOS_SECUREBOOT=1"
)

set "TPM_VER="
set "TPM_SRC="
if not "!PS_TPM!"=="-" (
    for /f "tokens=1 delims=," %%a in ("!PS_TPM!") do set "TPM_VER=%%a"
    if defined TPM_VER set "TPM_SRC=WMI"
)
if not defined TPM_VER (
    if exist "%SYSDIR%\tpmtool.exe" (
        tpmtool getdeviceinformation > "%WORKDIR%\tpm.txt" 2>nul
        findstr /i /r /c:"TPM Version: *2\." "%WORKDIR%\tpm.txt" >nul 2>&1
        if not errorlevel 1 (
            set "TPM_VER=2.0"
            set "TPM_SRC=tpmtool"
        )
    )
)
if not defined TPM_VER (
    reg query "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\MSFT0101" >nul 2>&1
    if not errorlevel 1 (
        set "TPM_VER=2.0"
        set "TPM_SRC=ACPI device ID"
    )
)

if not defined TPM_VER (
    call :row FAIL "TPM 2.0" "no TPM detected - required by FACEIT AC"
    set /a BIOS_WORK+=1
    set "BIOS_TPM=1"
) else (
    call :contains "!TPM_VER!" "2."
    if "!FOUND!"=="0" (
        call :row FAIL "TPM 2.0" "found TPM !TPM_VER! via !TPM_SRC! - version 2.0 is required"
        set /a BIOS_WORK+=1
        set "BIOS_TPM=1"
    ) else (
        call :row OK "TPM 2.0" "present, version !TPM_VER!, via !TPM_SRC!"
    )
)

if "%HAS_PS%"=="1" (
    if /i "!PS_HYPERV!"=="True" (
        call :row OK "CPU virtualization" "hypervisor running, so VT-x/AMD-V is on"
    ) else (
        call :row WARN "CPU virtualization" "hypervisor not running - enable VT-x or SVM in BIOS if VBS fails"
    )
) else (
    call :row INFO "CPU virtualization" "needs PowerShell to verify - check VT-x/SVM in BIOS"
)
goto :eof


:scan_boot
if "%BCD_OK%"=="0" (
    call :row FAIL "Boot configuration" "bcdedit returned nothing - cannot read the BCD store"
    goto :eof
)

call :bcd_absent "testsigning"       "Test signing"        TESTSIGNING "unsigned drivers can load"
call :bcd_absent "nointegritychecks" "Integrity checks"    NOINTEGRITY "kernel code integrity is disabled"
call :bcd_absent "debug"             "Kernel debugging"    DEBUG       "a kernel debugger can attach"
call :bcd_absent "flightsigning"     "Flight signing"      FLIGHTSIGN  "pre-release driver signatures are accepted"
call :bcd_absent "loadoptions"       "Custom load options" LOADOPTIONS "custom kernel load options are set"
call :bcd_absent "safeboot"          "Safe mode boot flag" SAFEBOOT    "the machine is pinned to Safe Mode"

set "HLT="
for /f "tokens=1,*" %%a in ('findstr /i /r /c:"^hypervisorlaunchtype " "%BCDFILE%" 2^>nul') do set "HLT=%%b"
if not defined HLT (
    call :row OK "Hypervisor launch type" "Auto, the BCD default"
) else (
    for /f "tokens=*" %%x in ("!HLT!") do set "HLT=%%x"
    call :contains "!HLT!" "Auto"
    if "!FOUND!"=="0" (
        call :row FAIL "Hypervisor launch type" "reads !HLT! - must be Auto for VBS/HVCI"
        set "NEED_HYPERVISOR=1"
        set /a CNT_FIXABLE+=1
    ) else (
        call :row OK "Hypervisor launch type" "Auto"
    )
)
goto :eof


:scan_security
set "DG=HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard"
set "DGS=HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
set "DGP=HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"

call :regval "%DG%" "EnableVirtualizationBasedSecurity"
if /i "!RV!"=="0x1" (
    call :row OK "VBS configured" "EnableVirtualizationBasedSecurity = 1"
) else if "!PS_VBS!"=="2" (
    call :row OK "VBS configured" "running on Windows defaults, no override needed"
) else (
    call :row WARN "VBS configured" "not enabled"
    set "NEED_VBS=1"
    set /a CNT_FIXABLE+=1
)

call :regval "%DGS%" "Enabled"
if /i "!RV!"=="0x1" (
    call :row OK "Memory Integrity, HVCI" "configured on"
) else if "!HVCI_RUN!"=="1" (
    call :row OK "Memory Integrity, HVCI" "running on Windows defaults"
) else (
    call :row WARN "Memory Integrity, HVCI" "not enabled"
    set "NEED_HVCI=1"
    set /a CNT_FIXABLE+=1
)

call :regval "HKLM\SYSTEM\CurrentControlSet\Control\CI\Config" "VulnerableDriverBlocklistEnable"
if /i "!RV!"=="0x1" (
    call :row OK "Vulnerable driver blocklist" "enabled"
) else if "!RVERR!"=="1" (
    call :row WARN "Vulnerable driver blocklist" "not configured"
    set "NEED_BLOCKLIST=1"
    set /a CNT_FIXABLE+=1
) else (
    call :row FAIL "Vulnerable driver blocklist" "explicitly disabled"
    set "NEED_BLOCKLIST=1"
    set /a CNT_FIXABLE+=1
)

call :regval "%DGP%" "EnableVirtualizationBasedSecurity"
set "P_VBS=!RV!"
call :regval "%DGP%" "HypervisorEnforcedCodeIntegrity"
set "P_HVCI=!RV!"

set "POL_OK=0"
if /i "!P_VBS!"=="0x1" if defined P_HVCI if not "!P_HVCI!"=="0x0" set "POL_OK=1"

if "!POL_OK!"=="1" (
    call :row OK "Enforced by Group Policy" "VBS and HVCI held on by policy"
) else (
    call :row INFO "Enforced by Group Policy" "not enforced - optional"
    set "NEED_POLICY=1"
    set /a CNT_OPTIONAL+=1
)
goto :eof


:scan_runtime
if not "%HAS_PS%"=="1" (
    call :row INFO "Runtime verification" "PowerShell unavailable - skipped"
    echo         %DIM%Configured and actually-running cannot be told apart without it.%CLR%
    echo         %DIM%Everything above was read straight from the registry and the BCD.%CLR%
    goto :eof
)

set "VBS_STAT=!PS_VBS!"

if "!VBS_STAT!"=="2" (
    call :row OK "VBS running" "active"
) else if "!VBS_STAT!"=="1" (
    call :row WARN "VBS running" "configured but not running - restart pending, or VT-x off in BIOS"
) else if "!VBS_STAT!"=="0" (
    call :row WARN "VBS running" "not running"
) else (
    call :row INFO "VBS running" "could not be determined"
)

if "!HVCI_RUN!"=="1" (
    call :row OK "Memory Integrity running" "active"
) else (
    call :row WARN "Memory Integrity running" "not active"
)

if /i "!PS_SB!"=="True" call :row OK "Secure Boot, UEFI query" "confirmed enabled"
if /i "!PS_SB!"=="False" call :row FAIL "Secure Boot, UEFI query" "confirmed disabled"
goto :eof


:scan_faceit
reg query "HKLM\SYSTEM\CurrentControlSet\Services" /f "faceit" /k >nul 2>&1
if errorlevel 1 (
    call :row INFO "FACEIT AC installed" "no FACEIT service found - install the client from faceit.com"
) else (
    call :row OK "FACEIT AC installed" "FACEIT service is registered"
)
goto :eof


:summary
echo.
call :rule
echo   %BLD%SUMMARY%CLR%      %GRN%OK %CNT_OK%%CLR%    %YEL%WARN %CNT_WARN%%CLR%    %RED%FAIL %CNT_FAIL%%CLR%
call :rule
echo.
call :log "SUMMARY ok=%CNT_OK% warn=%CNT_WARN% fail=%CNT_FAIL% fixable=%CNT_FIXABLE% firmware=%BIOS_WORK%"

if %BIOS_WORK% GTR 0 (
    echo   %RED%%BIOS_WORK% item^(s^) cannot be fixed by any script.%CLR% They live in your
    echo   firmware setup. Reboot, press the key shown on the motherboard
    echo   splash screen - usually %BLD%Del%CLR% or %BLD%F2%CLR% - and change these:
    echo.
    if defined LEGACY_BOOT (
        echo     %BLD%*%CLR%  Windows is installed in legacy BIOS/CSM mode, so Secure Boot
        echo        can never be enabled as things stand. Converting the disk to GPT
        echo        with %BLD%mbr2gpt.exe%CLR% and switching the firmware to UEFI fixes it, but
        echo        do that with a backup in hand - a wrong step here stops Windows
        echo        booting at all.
        echo.
    )
    if defined BIOS_SECUREBOOT (
        echo     %BLD%*%CLR%  Enable %BLD%Secure Boot%CLR%, usually under Boot or Security. If the
        echo        option is greyed out: set OS Type to "Windows UEFI mode", disable
        echo        CSM/Legacy support, and if it is still greyed out use "Restore
        echo        Factory Keys" to reload the Secure Boot key database.
        echo.
    )
    if defined BIOS_TPM (
        echo     %BLD%*%CLR%  Enable the %BLD%TPM%CLR%. AMD boards call it %BLD%fTPM%CLR% or "AMD PSP fTPM",
        echo        Intel boards call it %BLD%PTT%CLR% or "Intel Platform Trust Technology".
        echo        Both give you a firmware TPM 2.0 with no extra hardware needed.
        echo.
    )
    echo     %DIM%Change the firmware settings, boot back into Windows, then run%CLR%
    echo     %DIM%this script again to confirm they took.%CLR%
    echo.
)
goto :eof


:fix_all

call :fix_bcd TESTSIGNING "testsigning" "Test signing" "Turn off test signing" "Lets unsigned drivers load. FACEIT AC will not start while this is on."
call :fix_bcd NOINTEGRITY "nointegritychecks" "Integrity checks" "Re-enable kernel integrity checks" "nointegritychecks switches off driver signature verification entirely."
call :fix_bcd DEBUG "debug" "Kernel debugging" "Turn off kernel debugging" "An attachable kernel debugger is an instant anti-cheat block."
call :fix_bcd FLIGHTSIGN "flightsigning" "Flight signing" "Turn off flight signing" "Makes Windows accept pre-release driver signatures."
call :fix_bcd LOADOPTIONS "loadoptions" "Custom load options" "Clear custom kernel load options" "Usually DISABLE_INTEGRITY_CHECKS left behind by a driver hack."
if "%NEED_SAFEBOOT%"=="1" (
    call :fix_head "Clear the Safe Mode boot flag" "The machine is set to always boot into Safe Mode."
    call :confirm
    if /i "!ANS!"=="Y" (
        call :bcd_clear "safeboot" "Safe mode boot flag"
        bcdedit /deletevalue "{current}" safebootalternateshell >nul 2>&1
    )
)
if "%NEED_HYPERVISOR%"=="1" (
    call :fix_head "Set hypervisor launch type to Auto" "Required before VBS or Memory Integrity can start at boot."
    call :confirm
    if /i "!ANS!"=="Y" call :step "hypervisorlaunchtype = Auto" bcdedit /set "{current}" hypervisorlaunchtype Auto
)

if "%NEED_VBS%"=="1" (
    call :fix_head "Enable Virtualization Based Security" "Isolates the kernel behind the hypervisor. Costs a few percent of your framerate."
    call :confirm
    if /i "!ANS!"=="Y" (
        call :step "VBS: EnableVirtualizationBasedSecurity = 1" reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
        call :step "VBS: RequirePlatformSecurityFeatures = 1" reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v RequirePlatformSecurityFeatures /t REG_DWORD /d 1 /f
        call :step "VBS: vsmlaunchtype = Auto" bcdedit /set "{current}" vsmlaunchtype Auto
    )
)

if "%NEED_HVCI%"=="1" (
    call :fix_head "Enable Memory Integrity, HVCI" "Blocks unsigned code in the kernel, which is how most cheats get there."
    call :confirm
    if /i "!ANS!"=="Y" (
        call :step "HVCI: create scenario key" reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /f
        call :step "HVCI: Enabled = 1" reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 1 /f
        call :step "HVCI: Locked = 0" reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Locked /t REG_DWORD /d 0 /f
        echo         %DIM%If Memory Integrity still reads off after the restart, an installed%CLR%
        echo         %DIM%driver is incompatible. Windows Security, Device security, Core%CLR%
        echo         %DIM%isolation will name it. Old ASUS, MSI and Razer utilities are the%CLR%
        echo         %DIM%usual offenders.%CLR%
    )
)

if "%NEED_BLOCKLIST%"=="1" (
    call :fix_head "Enable the vulnerable driver blocklist" "Blocks the signed-but-exploitable drivers cheats load to reach the kernel."
    call :confirm
    if /i "!ANS!"=="Y" (
        call :step "Blocklist: create key" reg add "HKLM\SYSTEM\CurrentControlSet\Control\CI\Config" /f
        call :step "Blocklist: VulnerableDriverBlocklistEnable = 1" reg add "HKLM\SYSTEM\CurrentControlSet\Control\CI\Config" /v VulnerableDriverBlocklistEnable /t REG_DWORD /d 1 /f
    )
)

if "%NEED_POLICY%"=="1" (
    call :fix_head "OPTIONAL - enforce VBS and HVCI through Group Policy" "Stops other software quietly switching them back off. Harder to undo."
    echo         %DIM%Skip this if unsure. The settings above are enough for FACEIT.%CLR%
    call :confirm
    if /i "!ANS!"=="Y" (
        call :step "Policy: create key" reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /f
        call :step "Policy: EnableVirtualizationBasedSecurity = 1" reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
        call :step "Policy: RequirePlatformSecurityFeatures = 1" reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v RequirePlatformSecurityFeatures /t REG_DWORD /d 1 /f
        call :step "Policy: HypervisorEnforcedCodeIntegrity = 2" reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v HypervisorEnforcedCodeIntegrity /t REG_DWORD /d 2 /f
    )
)
goto :eof


:fix_bcd
if not "!NEED_%~1!"=="1" goto :eof
call :fix_head "%~4" "%~5"
call :confirm
if /i "!ANS!"=="Y" call :bcd_clear "%~2" "%~3"
goto :eof


:fix_head
echo.
echo   %BLD%%~1%CLR%
echo   %DIM%%~2%CLR%
goto :eof


:confirm
if "%APPLY_ALL%"=="1" (
    set "ANS=Y"
    echo      %DIM%auto-accepted%CLR%
    goto :eof
)
set "TRIES=0"
:confirm_loop
set /a TRIES+=1
if !TRIES! GTR 10 (
    set "ANS=N"
    goto :eof
)
set "ANS="
set /p "ANS=     Apply?  [Y]es  [N]o  [A]ll : "
if /i "!ANS!"=="Y" goto :eof
if /i "!ANS!"=="N" (
    echo      %DIM%skipped%CLR%
    goto :eof
)
if /i "!ANS!"=="A" (
    set "APPLY_ALL=1"
    set "ANS=Y"
    goto :eof
)
goto :confirm_loop


:step
set "STEP=%~1"
shift
set "CMDLINE="
:step_build
if "%~1"=="" goto :step_run
set "CMDLINE=!CMDLINE! %1"
shift
goto :step_build
:step_run
%CMDLINE% >nul 2>&1
set "RC=!errorlevel!"
if "!RC!"=="0" (
    echo      %GRN%[ done ]%CLR% !STEP!
    call :log "APPLIED !STEP!"
    set /a CNT_APPLIED+=1
    set "REBOOT_NEEDED=1"
) else (
    echo      %RED%[FAILED]%CLR% !STEP!   %DIM%exit code !RC!%CLR%
    call :log "FAILED  !STEP!  exit !RC!  cmd:!CMDLINE!"
    set /a CNT_FAILED+=1
)
goto :eof


:bcd_clear
bcdedit /deletevalue "{current}" %~1 >nul 2>&1
set "RC=!errorlevel!"
set "GONE=0"
bcdedit /enum "{current}" 2>nul | findstr /i /r /c:"^%~1 " >nul 2>&1
if errorlevel 1 set "GONE=1"
if "!RC!"=="0" if "!GONE!"=="1" (
    echo      %GRN%[ done ]%CLR% %~2 removed from the boot configuration
    call :log "APPLIED bcd deletevalue %~1"
    set /a CNT_APPLIED+=1
    set "REBOOT_NEEDED=1"
    goto :eof
)
echo      %RED%[FAILED]%CLR% %~2 is still set   %DIM%exit code !RC!%CLR%
call :log "FAILED  bcd deletevalue %~1  exit !RC!"
set /a CNT_FAILED+=1
goto :eof


:bcd_absent
findstr /i /r /c:"^%~1 " "%BCDFILE%" >nul 2>&1
if errorlevel 1 (
    call :row OK "%~2" "off, Windows default"
) else (
    call :row FAIL "%~2" "SET - %~4"
    set "NEED_%~3=1"
    set /a CNT_FIXABLE+=1
)
goto :eof


:row
set "_n=%~2                                     "
set "_n=!_n:~0,31!"
set "_d=%~3"
set "_s=%CYN%[ -- ]%CLR%"
if /i "%~1"=="OK" (set "_s=%GRN%[ OK ]%CLR%" & set /a CNT_OK+=1)
if /i "%~1"=="WARN" (set "_s=%YEL%[WARN]%CLR%" & set /a CNT_WARN+=1)
if /i "%~1"=="FAIL" (set "_s=%RED%[FAIL]%CLR%" & set /a CNT_FAIL+=1)
echo(  !_s!  !_n! %DIM%!_d!%CLR%
call :log "  [%~1] %~2 : !_d!"
goto :eof

:section
echo.
echo   %CYN%%~1%CLR%
echo   %DIM%--------------------------------------------------------------------%CLR%
call :log ""
call :log "--- %~1"
goto :eof

:rule
echo   %DIM%====================================================================%CLR%
goto :eof

:banner
echo.
echo   %BLD%%CYN%FACEIT ANTICHEAT HELPER%CLR%   %DIM%v%APP_VER%%CLR%
echo   %DIM%%APP_URL%%CLR%
call :rule
goto :eof

:ask
set "TRIES=0"
:ask_loop
set /a TRIES+=1
if !TRIES! GTR 10 (
    set "ANS=N"
    goto :eof
)
set "ANS="
set /p "ANS=%~1 [Y/N]: "
if /i "!ANS!"=="Y" goto :eof
if /i "!ANS!"=="N" goto :eof
goto :ask_loop

:anykey
echo   %DIM%Press any key to continue...%CLR%
pause >nul
goto :eof

:log
if not defined LOGFILE goto :eof
set "_l=%~1"
>>"%LOGFILE%" echo(!_l!
goto :eof


:splash
if not defined ESC (
    echo.
    echo   %APP_URL%
    echo.
    goto :eof
)
call :calibrate
cls
echo.
echo.
echo   %DIM%FACEIT ANTICHEAT HELPER%CLR%
echo.
call :strlen "%APP_URL%"
set /a "_last=LEN-1"
<nul set /p "=%ESC%[1G   %CYN%"
for /l %%i in (0,1,%_last%) do (
    <nul set /p "=!APP_URL:~%%i,1!"
    call :nap 1
)
<nul set /p "=%CLR%"
call :nap 6

set /a "_sweep=LEN"
for /l %%p in (0,3,%_sweep%) do (
    call :splash_frame %%p
    call :nap 2
)
call :splash_frame %_sweep%
call :nap 3

set "P0=%ESC%[90m"
set "P1=%ESC%[36m"
set "P2=%ESC%[96m"
set "P3=%ESC%[1m%ESC%[96m"
set "P4=%ESC%[1m%ESC%[97m"
for /l %%r in (1,1,2) do (
    for %%c in (3 4 3 2 1 0 1 2) do (
        call :pulse_frame %%c
        call :nap 2
    )
)
call :pulse_frame 2
call :nap 4
echo.
echo.
goto :eof

:pulse_frame
<nul set /p "=%ESC%[1G   !P%1!%APP_URL%%CLR%%ESC%[K"
goto :eof

:splash_frame
set /a "_a=%1"
set /a "_b=_a+4"
set "_pre=!APP_URL:~0,%_a%!"
set "_hot=!APP_URL:~%_a%,4!"
set "_post=!APP_URL:~%_b%!"
<nul set /p "=%ESC%[1G   %CYN%!_pre!%ESC%[1m%ESC%[97m!_hot!%ESC%[0m%CYN%!_post!%CLR%%ESC%[K"
goto :eof


:nap
set /a "_sp=SPIN*%1"
for /l %%z in (1,1,%_sp%) do rem
goto :eof

:calibrate
set "SPIN=20000"
set /a "_cn=100000"
:cal_try
call :clock_now
set /a "_ct0=CLK"
for /l %%z in (1,1,%_cn%) do rem
call :clock_now
set /a "_cel=(CLK-_ct0)*10"
if %_cel% LSS 0 set /a "_cel=_cel+86400000"
if %_cel% LSS 80 (
    set /a "_cn=_cn*4"
    if !_cn! LSS 40000000 goto :cal_try
)
if %_cel% LSS 1 set "_cel=1"
set /a "SPIN=_cn*12/_cel"
if %SPIN% LSS 200 set "SPIN=200"
if %SPIN% GTR 4000000 set "SPIN=4000000"
goto :eof
:clock_now
for /f "tokens=1-4 delims=:., " %%a in ("!TIME!") do set /a "CLK=(((100%%a %% 100)*60+(100%%b %% 100))*60+(100%%c %% 100))*100+(100%%d %% 100)"
goto :eof

:strlen
set "_sl=%~1"
set "LEN=0"
:strlen_loop
if defined _sl (
    set "_sl=!_sl:~1!"
    set /a LEN+=1
    goto :strlen_loop
)
goto :eof


:contains
set "FOUND=0"
set "_hay=%~1"
set "_ned=%~2"
if not defined _hay goto :eof
if not defined _ned goto :eof
set "_cut=!_hay:%_ned%=!"
if not "!_cut!"=="!_hay!" set "FOUND=1"
goto :eof


:regval
set "RV="
for /f "tokens=2,*" %%a in ('reg query "%~1" /v "%~2" %REG64% 2^>nul ^| findstr /i /r /c:"^ *%~2  *REG_"') do set "RV=%%b"
if defined RV (set "RVERR=0") else (set "RVERR=1")
goto :eof


:init
set "REG64="
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "REG64=/reg:64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "REG64=/reg:64"
reg query "HKLM\SOFTWARE" %REG64% >nul 2>&1 || set "REG64="

set "HAS_PS=0"
set "PS_TPM=-"
set "PS_HYPERV=-"
set "PS_VBS=-"
set "PS_SVC=-"
set "PS_SB=-"
for /f "usebackq tokens=1-5 delims=#" %%a in (`powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$t='-';$h='-';$v='-';$s='-';$b='-';try{$x=(Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -EA Stop).SpecVersion;if($x){$t=$x}}catch{};try{$x=[string](Get-CimInstance Win32_ComputerSystem -EA Stop).HypervisorPresent;if($x){$h=$x}}catch{};try{$d=Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -EA Stop;$v=[string]$d.VirtualizationBasedSecurityStatus;$x=($d.SecurityServicesRunning -join '.');if($x){$s=$x}}catch{};try{$x=[string](Confirm-SecureBootUEFI);if($x){$b=$x}}catch{};'{0}#{1}#{2}#{3}#{4}' -f $t,$h,$v,$s,$b" 2^>nul`) do (
    set "HAS_PS=1"
    set "PS_TPM=%%a"
    set "PS_HYPERV=%%b"
    set "PS_VBS=%%c"
    set "PS_SVC=%%d"
    set "PS_SB=%%e"
)
set "HVCI_RUN=0"
if not "!PS_SVC!"=="-" (
    call :contains "!PS_SVC!" "2"
    if "!FOUND!"=="1" set "HVCI_RUN=1"
)

set "WORKDIR=%TEMP%\faceit-anticheat-helper"
if not exist "%WORKDIR%" md "%WORKDIR%" >nul 2>&1
if not exist "%WORKDIR%" set "WORKDIR=%TEMP%"

set "LOGFILE=%~dp0faceit-anticheat-helper.log"
set "WTEST=%~dp0faceit-anticheat-helper.tmp"
copy /y nul "%WTEST%" >nul 2>&1 || set "LOGFILE=%WORKDIR%\faceit-anticheat-helper.log"
del /q "%WTEST%" >nul 2>&1

for %%v in (CLR GRN RED YEL CYN DIM BLD) do set "%%v="
call :regval "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuild"
set "B=!RV!"
if not defined B set "B=0"
if !B! GEQ 10586 call :set_colors
goto :eof

:set_colors
set "ESC="
for /f %%a in ('echo prompt $E ^| %ComSpec%') do set "ESC=%%a"
if not defined ESC goto :eof
for %%v in ("CLR=0" "GRN=92" "RED=91" "YEL=93" "CYN=96" "DIM=90" "BLD=1") do (
    for /f "tokens=1,2 delims==" %%x in (%%v) do set "%%x=%ESC%[%%ym"
)
goto :eof


:elevate
echo.
echo   This tool reads the boot configuration and writes to
echo   HKEY_LOCAL_MACHINE, so it needs administrator rights.
echo.
echo   Requesting elevation...

if exist "%SYSDIR%\WindowsPowerShell\v1.0\powershell.exe" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '/elevated' -Verb RunAs" >nul 2>&1
    exit /b 0
)

set "VBSFILE=%TEMP%\faceit_elevate.vbs"
>"%VBSFILE%" echo Set sh = CreateObject("Shell.Application")
>>"%VBSFILE%" echo sh.ShellExecute "%~f0", "/elevated", "", "runas", 1
if exist "%VBSFILE%" (
    cscript //nologo "%VBSFILE%" >nul 2>&1
    set "RC=!errorlevel!"
    del /q "%VBSFILE%" >nul 2>&1
    if "!RC!"=="0" exit /b 0
)

:no_admin
echo.
echo   Could not elevate automatically.
echo.
echo   Close this window, right-click the file and choose
echo   "Run as administrator".
echo.
pause
exit /b 1
