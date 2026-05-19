# Troubleshooting Guide

## Issue 1: Mouse Cursor Not Visible on Physical Hardware

**Symptom:** Popup appears and Tab key works but mouse cursor is invisible or frozen.

**Root Cause:** On physical hardware, USB and touchpad drivers are not fully initialized when the registration form appears during early OOBE. Virtual machines use PS/2 emulated mouse which loads instantly, which is why this issue does not appear in VM testing.

**Solutions:**
1. Verify the 10-second sleep is present before form display
2. Check cursor timer is starting in the form's Shown event
3. Increase sleep to 15 seconds on slower hardware
4. Test on actual physical device models, not just VMs

---

## Issue 2: Window Not Receiving Keyboard Focus

**Symptom:** Registration form appears but Tab key and keyboard input do not work. Must click the window first.

**Root Cause:** The SCCM task sequence progress window holds foreground focus. The registration form appears but does not steal focus automatically.

**Solutions:**
1. Ensure "Allow users to interact" is **unchecked** in the SCCM task sequence step
2. Verify WindowHelper Win32 API code is included in the script
3. Confirm SetForegroundWindow is called in the Shown event handler
4. Check that the focus sequence executes after the 200ms render delay

---

## Issue 3: Device Not Appearing in Autopilot Portal

**Symptom:** Script reports success but device does not appear in Intune Autopilot devices list.

**Solutions:**
1. Check that the client secret has not expired
2. Verify app registration permissions are granted with admin consent
3. Test Graph API access using Graph Explorer (developer.microsoft.com/graph/graph-explorer)
4. Wait 10 to 15 minutes for Intune sync cycle to complete
5. Check Intune Admin Center > Devices > Windows enrollment > Devices

---

## Issue 4: SCCM Client Not Removed After OOBE

**Symptom:** SCCM client still present after provisioning completes.

**Solutions:**
1. Verify SetupComplete.cmd was copied to `C:\Windows\Setup\Scripts\` during task sequence
2. Check `C:\Windows\Temp\SetupComplete.log` for execution evidence
3. Confirm the copy command used `/y` flag to overwrite existing files
4. Verify the computer restart step executed after the OOBE registration step

---

## Issue 5: Authentication Failure

**Symptom:** Script fails with authentication error during Graph API call.

**Solutions:**
1. Verify TenantId, ClientId, and ClientSecret values are correct
2. Check that admin consent has been granted for the app registration
3. Confirm the app has `DeviceManagementServiceConfig.ReadWrite.All` permission
4. Check network connectivity to `login.microsoftonline.com:443`
5. Verify client secret has not expired

---

## Issue 6: Hardware Hash Collection Failure

**Symptom:** Script fails when attempting to collect hardware hash from WMI.

**Solutions:**
1. Confirm the device supports WMI MDM_DevDetail_Ext01 class
2. Verify script is running with administrative rights
3. Check WMI service is running on the device
4. Try running `Get-CimInstance -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01` manually to test

---

## Checking SetupComplete.log

After provisioning, check the cleanup log:

```cmd
type C:\Windows\Temp\SetupComplete.log
```

This log shows whether the SCCM client uninstallation ran and whether all artifacts were removed successfully.
