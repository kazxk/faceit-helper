# FACEIT Anticheat Helper

Finds out why FACEIT Anti-Cheat will not start on a Windows machine and fixes
what Windows lets a script fix. For everything else it names the BIOS setting
you have to change yourself.

## Run it

Right-click `faceit-anticheat-helper.cmd` and run as administrator. If you
forget, it asks for admin rights itself.

```
[1]  Scan only          report, change nothing
[2]  Scan and fix       report, then ask about each item
[3]  Open the log file
[4]  Exit
```

Option 1 changes nothing. Option 2 asks before every single change.

## What it checks

| Section | Checks |
| --- | --- |
| System | Windows build, 64-bit, UEFI or legacy BIOS, virtual machine |
| Firmware | Secure Boot, TPM 2.0, CPU virtualization |
| Boot config | test signing, integrity checks, kernel debugging, flight signing, custom load options, Safe Mode flag, hypervisor launch type |
| Security | VBS, Memory Integrity (HVCI), vulnerable driver blocklist, Group Policy |
| Runtime | whether VBS and Memory Integrity are running, not only configured |
| Client | whether the FACEIT service is installed |

## What it fixes

- Removes `testsigning`, `nointegritychecks`, `debug`, `flightsigning`,
  `loadoptions` and `safeboot` from the boot configuration
- Sets `hypervisorlaunchtype` and `vsmlaunchtype` to Auto
- Enables VBS and Memory Integrity
- Enables the vulnerable driver blocklist
- Enforces VBS and HVCI through Group Policy, if you want it

Every change needs a restart. The script offers one at the end.

## What it cannot fix

These live in firmware. The script reports them and prints the option name to
look for:

- Secure Boot disabled
- No TPM 2.0. AMD boards call it fTPM, Intel boards call it PTT
- Windows installed in legacy BIOS or CSM mode, where Secure Boot is impossible
- Running in a virtual machine, which FACEIT AC blocks

## Requirements

Windows 10 1809 or newer, 64-bit, administrator rights.

## Notes

- There is no undo. The script only turns security features on.
- VBS and Memory Integrity cost a few percent of your framerate.
- Memory Integrity will refuse to turn on if an installed driver is
  incompatible. Windows Security names that driver under Core isolation.
- The log is written next to the script, or to `%TEMP%` if that folder is read
  only.

