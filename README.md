# Automated Autopilot Provisioning Framework
### Hybrid SCCM-to-Intune Zero-Touch Device Registration

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## Overview

This framework automates the registration of non-domain-joined Windows endpoints into Microsoft Intune Autopilot during the SCCM Out-of-Box Experience (OOBE). It addresses a specific enterprise challenge: organizations transitioning from on-premises SCCM management to cloud-based Intune management where devices have lost domain connectivity and cannot be provisioned through conventional means.

**The Problem:**

Traditional reprovisioning of non-domain-joined enterprise endpoints requires either a full Dell Cloud BIOS reset (6.5 hours per device) or manual bootable USB reimaging with manual Intune portal upload (3-4 hours per device). Neither method scales for large enterprise deployments.

**The Solution:**

This framework reduces per-device provisioning time to approximately 30 minutes through a single 30-second technician interaction during OOBE, with all registration, group assignment, and Intune handoff handled automatically.

---

## Key Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Per-device provisioning time | 6.5 hours | 30 minutes | 92% reduction |
| Manual technician steps | 7+ steps | 1 step (30 seconds) | 86% reduction |
| Error rate | High (manual CSV, portal upload) | Near zero | Automated pipeline |
| Scale capability | Limited | Thousands of devices | Linear scaling |

---

## How It Works

The framework uses a five-stage automated pipeline:

```
Stage 1: SCCM Task Sequence
├── Configure BIOS (Dell/HP/Lenovo)
├── Deploy Windows 11 image via WinPE
├── Install hardware drivers by model
├── Install SCCM client (temporary)
├── Copy SetupComplete.cmd cleanup script
└── Sysprep → reboot to OOBE

Stage 2: OOBE Interactive Registration
├── ServiceUI.exe bridges Session 0 → Session 1
├── Popup UI appears for technician
├── Technician selects organizational unit (30 seconds)
└── Hardware hash collected from firmware automatically

Stage 3: Cloud Registration
├── Authenticate to Microsoft Graph API
├── Register device in Autopilot with group tag
└── Confirm registration success

Stage 4: Automatic Cleanup
├── Windows executes SetupComplete.cmd on reboot
├── SCCM client uninstalled automatically
├── All SCCM artifacts removed
└── Device ready for clean Autopilot enrollment

Stage 5: Intune Management
├── Device joins Azure AD dynamic group (by group tag)
├── Department-specific apps deployed automatically
└── Configuration policies applied
```

---

## Technical Innovations

### 1. Temporary SCCM Client Pattern
The framework installs the SCCM client specifically to leverage its session management capabilities during OOBE, then removes it automatically via SetupComplete.cmd before Autopilot enrollment begins. This eliminates dual-management conflicts while enabling SCCM's deployment infrastructure during the provisioning phase.

### 2. OOBE Session Bridging
Uses ServiceUI.exe to bridge Windows session isolation during OOBE, enabling an interactive graphical interface to appear in the technician-facing session (Session 1) while the SCCM task sequence runs in the non-interactive background session (Session 0).

### 3. Physical Hardware Cursor Management
Multi-layer cursor visibility management addresses USB and touchpad driver initialization timing on physical hardware during early OOBE. Implements Win32 ShowCursor API with continuous timer refresh to maintain cursor visibility across all hardware configurations.

### 4. Graph API Registration During OOBE
Registers devices directly in Autopilot via Microsoft Graph API during the OOBE phase, before Autopilot enrollment begins, using hardware hash data collected from device firmware. Eliminates manual CSV export and portal upload entirely.

### 5. Aggressive Window Activation
Win32 API sequence (SetWindowPos → BringWindowToTop → SetForegroundWindow → SetFocus) ensures the registration interface receives keyboard focus within the OOBE environment where the SCCM progress window holds foreground focus by default.

---

## Prerequisites

### Azure / Intune Setup

1. **Azure AD App Registration** with the following permissions:
   - `DeviceManagementServiceConfig.ReadWrite.All`
   - `Directory.Read.All`
   - Admin consent granted

2. **Azure AD Dynamic Device Groups** configured per organizational unit:
   ```
   (device.displayName -startsWith "DEPT-") or
   (device.devicePhysicalIds -any (_ -contains "[OrderID]:DEPT"))
   ```

3. **Applications assigned** to dynamic groups in Intune

### SCCM Infrastructure

- SCCM / Configuration Manager environment
- ServiceUI.exe from Microsoft Deployment Toolkit (MDT)
- Distribution point accessible from OOBE network context
- Network access to:
  - `login.microsoftonline.com:443`
  - `graph.microsoft.com:443`
  - `*.manage.microsoft.com:443`

---

## Repository Contents

```
autopilot-provisioning-framework/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── scripts/
│   ├── Import-AutopilotPopup.ps1      # Main OOBE registration script
│   └── SetupComplete.cmd              # Automatic SCCM cleanup script
├── task-sequence/
│   └── TaskSequence-Design.md         # SCCM task sequence configuration guide
└── docs/
    ├── Setup-Guide.md                 # Complete setup instructions
    ├── Troubleshooting.md             # Common issues and solutions
    └── Architecture.md               # Technical architecture overview
```

---

## Quick Start

### Step 1: Configure Azure AD App Registration

```powershell
# Update these values in Import-AutopilotPopup.ps1
$TenantId     = "YOUR_TENANT_ID"
$ClientId     = "YOUR_CLIENT_ID"
$ClientSecret = "YOUR_CLIENT_SECRET"  # Use Azure Key Vault in production
```

### Step 2: Create SCCM Package

Create a package containing:
- `Import-AutopilotPopup.ps1`
- `SetupComplete.cmd`
- `ServiceUI.exe` (from MDT installation)

### Step 3: Configure Task Sequence

Add the following step after Sysprep:

```
Type: Run Command Line
Name: Register Device in Autopilot
Command: ServiceUI.exe -process:tsprogressui.exe powershell.exe -ExecutionPolicy Bypass -File Import-AutopilotPopup.ps1
Package: [Your Autopilot Package]
Run with administrative rights: YES
Allow users to interact: NO  ← CRITICAL
```

### Step 4: Deploy and Test

Test on a virtual machine first, then validate on physical hardware.

---

## Customization

### Organizational Units

Edit the `$agencies` array in `Import-AutopilotPopup.ps1` to match your organization's departments or business units:

```powershell
$agencies = @(
    "IT",
    "Finance",
    "HR",
    "Operations",
    "Sales"
) | Sort-Object
```

Each entry becomes a group tag that Azure AD dynamic groups use for automatic app assignment.

---

## Security Considerations

- Store client secrets in Azure Key Vault rather than hardcoding in scripts
- Rotate client secrets every 6 to 12 months
- Limit app registration permissions to minimum required
- Audit Autopilot registrations periodically
- All Graph API calls use HTTPS enforced by the endpoint

---

## Troubleshooting

See `docs/Troubleshooting.md` for solutions to common issues including:

- Mouse cursor not visible on physical hardware
- Window not receiving keyboard focus
- Device not appearing in Autopilot portal after registration
- SCCM client not removed after OOBE
- Network timeout during registration

---

## License

MIT License. Free to use and adapt for your organization.

---

## Author

**Narasimha Rao Alugoju**  
Applications Systems Architect Advisor  
Peraton Enterprise Solutions LLC  
Herndon, Virginia, USA

Published research on enterprise endpoint management:
- Alugoju, N. "Modern Endpoint Management: Enhancing Security and Compliance in the Enterprise." Journal of Recent Trends in Computer Science and Engineering, 2023.
- Alugoju, N. "Data Protection in the Cloud." IJRASET, 2024.

---

*This framework was developed to solve a real-world enterprise provisioning challenge and validated in production deployment across a large-scale enterprise environment.*
