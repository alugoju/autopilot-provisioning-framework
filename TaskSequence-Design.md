# SCCM Task Sequence Design

## Overview

This document describes the complete SCCM task sequence configuration for the Automated Autopilot Provisioning Framework.

## Task Sequence Structure

```
Task Sequence: Autopilot Pre-Provisioning
│
├── Phase 1: BIOS Configuration (WinPE)
│   ├── Install WinPE HAPI Driver
│   ├── Clear BIOS Password (if applicable)
│   └── Configure UEFI/Secure Boot settings
│
├── Phase 2: Windows Deployment (WinPE)
│   ├── Restart in Windows PE
│   ├── Clean Drive (Format and partition)
│   ├── Partition Disk 0 - UEFI (GPT layout)
│   ├── Apply Windows OS Image (Windows 11 23H2)
│   └── Apply Windows Settings
│
├── Phase 3: Driver Injection
│   └── Apply Driver Package
│       (Conditional: based on device model)
│       ├── Dell Latitude models
│       ├── HP EliteBook models
│       └── Lenovo ThinkPad models
│
└── Phase 4: OOBE Preparation
    ├── Setup Windows and ConfigMgr
    │   └── Install SCCM client: YES
    │       (Temporary - removed by SetupComplete.cmd)
    │
    ├── Copy Cleanup Script
    │   └── Command: xcopy ".\SetupComplete.cmd" "C:\Windows\Setup\Scripts\" /y
    │       Package: Autopilot Registration Tools
    │
    ├── Sysprep
    │   └── Command: C:\Windows\System32\Sysprep\sysprep.exe /oobe /quiet /quit
    │       (Prepares Windows for OOBE, triggers reboot)
    │
    ├── Upload Hardware Hash Popup
    │   └── Command: ServiceUI.exe -process:tsprogressui.exe
    │               powershell.exe -ExecutionPolicy Bypass
    │               -File Import-AutopilotPopup.ps1
    │       Package: Autopilot Registration Tools
    │       Run with admin rights: YES
    │       Allow users to interact: NO  ← CRITICAL
    │
    └── Restart Computer
        (Windows executes SetupComplete.cmd automatically)
        (SCCM client removed before Autopilot enrollment)
```

## Critical Configuration Notes

### Allow Users to Interact — Must Be UNCHECKED

In the Upload Hardware Hash Popup step, the option **"Allow users to interact with this program"** must be **unchecked**.

ServiceUI.exe handles session management independently. If this option is checked, both SCCM and ServiceUI.exe attempt to manage session switching simultaneously, causing:
- Mouse cursor visibility conflicts
- Window activation failures
- Desktop switching conflicts

### Sysprep Command

Use `/quiet /quit` instead of `/reboot` to allow the task sequence to control the reboot timing:

```
C:\Windows\System32\Sysprep\sysprep.exe /oobe /quiet /quit
```

### SCCM Package Contents

Create one SCCM package containing:
- `Import-AutopilotPopup.ps1`
- `SetupComplete.cmd`
- `ServiceUI.exe` (copied from MDT installation at `C:\Program Files\Microsoft Deployment Toolkit\Templates\Distribution\Tools\x64\`)

## Azure AD Dynamic Group Configuration

Create one dynamic device group per organizational unit. Use this membership rule pattern:

```
(device.displayName -startsWith "DEPT-") or
(device.devicePhysicalIds -any (_ -contains "[OrderID]:DEPT"))
```

Replace `DEPT` with your organizational unit identifier. The second condition matches on the Autopilot OrderID property which corresponds to the group tag assigned during registration.

## Network Requirements

OOBE devices must be able to reach the following endpoints on port 443:
- `login.microsoftonline.com`
- `graph.microsoft.com`
- `*.manage.microsoft.com`

Ensure firewall and proxy rules allow these connections from the provisioning network segment.
