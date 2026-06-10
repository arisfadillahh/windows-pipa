param(
  [string]$DriverRoot = "C:\woa\drivers"
)

$ErrorActionPreference = "Continue"
$Log = "C:\woa\install-drivers-no-power.log"
New-Item -ItemType Directory -Force -Path "C:\woa" | Out-Null

function Log {
  param([string]$Message)
  $line = "{0}  {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
  $line | Tee-Object -FilePath $Log -Append
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Log "Self-elevating"
  $args = "-NoProfile -ExecutionPolicy Bypass -File `"C:\woa\install-drivers-no-power.ps1`" -DriverRoot `"$DriverRoot`""
  Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs
  exit
}

Log "=== install-drivers-no-power ==="
Log "DriverRoot=$DriverRoot"
Log "This script intentionally skips PMIC, PEP, PIL, PCIe, SCM, SMMU, IOMMU, SPMI, battery, and USB-C power-role drivers."

$disableServices = @(
  "qcppx", "qcPILC", "qcpil", "qcpil8250",
  "qcpmic", "qcpmicapps", "qcpmiceic", "qcpmicext", "qcpmicglink", "qcpmgpio", "qcpmictcc",
  "qcpep", "qciommu", "qcsmmu", "qcscm", "qcspmi",
  "qcbattmngr", "qcbattminiclass", "qcwlan"
)
foreach ($svc in $disableServices) {
  $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
  if (Test-Path $key) {
    Set-ItemProperty -Path $key -Name Start -Type DWord -Value 4
    Log "Disabled service $svc"
  }
}

$allow = @(
  "qcdx8250*.inf",
  "qcdx_ffu8250*.inf",
  "qdcmlib8250*.inf",
  "nt36xxx*.inf",
  "NanosicFilter*.inf"
)

$block = @(
  "qcppx*.inf", "qcpil*.inf", "*PILC*.inf",
  "qcpmic*.inf", "qcpep*.inf", "qcscm*.inf", "qcsmmu*.inf", "qciommu*.inf", "qcspmi*.inf",
  "qcbatt*.inf", "qcusbctcpm*.inf", "qcusbcucsi*.inf",
  "*mbb*.inf", "*wmril*.inf", "*qcmbb*.inf", "*cellular*.inf", "*modem*.inf", "*qcgnss*.inf", "qcwlan8250*.inf"
)

$drivers = Get-ChildItem -LiteralPath $DriverRoot -Recurse -Filter *.inf -ErrorAction SilentlyContinue
$selected = foreach ($inf in $drivers) {
  $name = $inf.Name
  $isAllowed = $false
  foreach ($pat in $allow) {
    if ($name -like $pat) { $isAllowed = $true; break }
  }
  foreach ($pat in $block) {
    if ($name -like $pat) { $isAllowed = $false; Log "SKIP blocked $($inf.FullName)"; break }
  }
  if ($isAllowed) { $inf }
}

Log ("Selected {0} driver INF(s)" -f @($selected).Count)
foreach ($inf in $selected) {
  Log "INSTALL $($inf.FullName)"
  $out = & pnputil.exe /add-driver "$($inf.FullName)" /install 2>&1
  $out | Out-File -FilePath $Log -Append
  Log ("pnputil exit={0}" -f $LASTEXITCODE)
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\woa\dump-woa-status.ps1" | Out-Null
Log "=== done ==="

