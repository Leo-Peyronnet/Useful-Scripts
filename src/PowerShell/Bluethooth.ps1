# Dump Windows Bluetooth encryption keys + Friendly Names for dual-boot
# Compatible with PowerShell 5.1 (Windows default). Run as SYSTEM via PsExec64.exe -s powershell -ExecutionPolicy Bypass -File this.ps1 [web:23][attached_file:1]

$KeysRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
$NamesRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"

# Load device names hashtable (MAC -> Name)
$deviceNames = @{}
$namesKey = Get-Item -Path $NamesRegPath -ErrorAction SilentlyContinue
if ($namesKey) {
    $namesKey.GetSubKeyNames() | ForEach-Object {
        $mac = ($_ -replace '[^0-9A-F]', '').ToUpper()
        try {
            $subKey = $namesKey.OpenSubKey($_)
            $nameBytes = $subKey.GetValue("Name")
            if ($nameBytes) {
                $name = ($nameBytes | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
                $deviceNames[$mac] = $name
            }
        }
        catch { }
    }
}

$btAdapters = Get-ChildItem -Path $KeysRegPath -ErrorAction SilentlyContinue
if (-not $btAdapters) {
    Write-Output "No Bluetooth adapters found or access denied. Run as SYSTEM."
    exit
}

foreach ($btAdapter in $btAdapters) {
    $adapterMac = $btAdapter.PSChildName.ToUpper()
    Write-Output "`n=== Adapter: $adapterMac ==="

    # Classic BT
    Write-Output "`nClassic BT devices:"
    $classicDevices = $btAdapter.GetValueNames() | Where-Object { $_ -ne "MasterIRK" }
    foreach ($devMac in $classicDevices) {
        $cleanMac = ($devMac -replace '[^0-9A-F]', '').ToUpper()
        if ($deviceNames.ContainsKey($cleanMac)) { $name = $deviceNames[$cleanMac] } else { $name = "Unknown" }
        try {
            $keyBytes = $btAdapter.GetValue($devMac)
            $hexKey = ($keyBytes | ForEach-Object { "{0:X2}" -f $_ }) -join ""
            Write-Output "$cleanMac ($name) : $hexKey"
        }
        catch {
            Write-Output "$cleanMac ($name) : Error reading key"
        }
    }

    # LE/Modern BT
    Write-Output "`nLE/Modern BT devices:"
    $leDevices = $btAdapter.GetSubKeyNames()
    foreach ($devReg in $leDevices) {
        $cleanMac = ($devReg -replace '[^0-9A-F]', '').ToUpper()
        if ($deviceNames.ContainsKey($cleanMac)) { $name = $deviceNames[$cleanMac] } else { $name = "Unknown" }
        Write-Output "`n-- Device: $cleanMac ($name) --"
        try {
            $devSubKey = $btAdapter.OpenSubKey($devReg)
            if ($devSubKey) {
                # LTK
                $ltk = $devSubKey.GetValue("LTK")
                if ($ltk -and $ltk -is [array]) {
                    Write-Output "LTK: $(($ltk | ForEach-Object { '{0:X2}' -f $_ }) -join '')"
                }

                # ERand
                $erand = $devSubKey.GetValue("ERand")
                if ($null -ne $erand) {
                    try {
                        if ($erand -is [int64]) {
                            $erandBytes = [BitConverter]::GetBytes($erand)
                            $erandHex = ($erandBytes | ForEach-Object { '{0:X2}' -f $_ }) -join ''
                            Write-Output "ERand (hex): $erandHex"
                            Write-Output "ERand (dec): $erand"
                        } elseif ($erand -is [array]) {
                            $erandHex = ($erand | ForEach-Object { '{0:X2}' -f $_ }) -join ''
                            Write-Output "ERand (hex bytes): $erandHex"
                        }
                    }
                    catch {
                        Write-Output "ERand: Failed - Raw: $erand"
                    }
                }

                # EDIV
                $ediv = $devSubKey.GetValue("EDIV")
                if ($null -ne $ediv) { Write-Output "EDIV: $ediv" }

                # IRK
                $irk = $devSubKey.GetValue("IRK")
                if ($irk -and $irk -is [array]) { Write-Output "IRK: $(($irk | ForEach-Object { '{0:X2}' -f $_ }) -join '')" }

                # CSRK
                $csk = $devSubKey.GetValue("CSRK")
                if ($csk -and $csk -is [array]) { Write-Output "CSRK: $(($csk | ForEach-Object { '{0:X2}' -f $_ }) -join '')" }
            }
        }
        catch {
            Write-Output "Error processing $cleanMac`: $($_.Exception.Message)"
        }
    }
}
