param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,
  [string]$CertificateBase64 = $env:SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_BASE64,
  [string]$CertificatePassword = $env:SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_PASSWORD,
  [string]$TimestampUrl = $env:SHOWRUNNER_WINDOWS_TIMESTAMP_URL,
  [switch]$RequireSignature
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BundlePath -PathType Container)) {
  throw "Windows bundle was not found: $BundlePath"
}

$targets = @(
  Get-ChildItem -LiteralPath $BundlePath -Recurse -File |
    Where-Object { $_.Extension -in @('.exe', '.dll') }
)
if ($targets.Count -eq 0) {
  throw "Windows bundle contains no executable signing targets: $BundlePath"
}

if ([string]::IsNullOrWhiteSpace($CertificateBase64)) {
  if ($RequireSignature) {
    throw 'A Windows signing certificate is required but SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_BASE64 is empty.'
  }
  Write-Host 'Windows signing skipped: no certificate was configured.'
  exit 0
}

$signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($null -eq $signtool) {
  $sdkRoots = @(
    'C:\Program Files (x86)\Windows Kits\10\bin',
    'C:\Program Files\Windows Kits\10\bin'
  )
  $signtool = $sdkRoots |
    Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object {
      Get-ChildItem -LiteralPath $_ -Filter signtool.exe -Recurse -File -ErrorAction SilentlyContinue
    } |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
}
if ($null -eq $signtool) {
  throw 'signtool.exe was not found. Install the Windows SDK before signing.'
}
$signtoolPath = if ($signtool.PSObject.Properties.Name -contains 'Source') {
  $signtool.Source
} else {
  $signtool.FullName
}
if ([string]::IsNullOrWhiteSpace($signtoolPath)) {
  throw 'signtool.exe path could not be resolved.'
}

$certificatePath = Join-Path ([IO.Path]::GetTempPath()) "showrunner-sign-$([guid]::NewGuid().ToString('N')).pfx"
try {
  try {
    [IO.File]::WriteAllBytes(
      $certificatePath,
      [Convert]::FromBase64String($CertificateBase64)
    )
  } catch {
    throw "The Windows signing certificate is not valid base64: $($_.Exception.Message)"
  }

  foreach ($target in $targets) {
    $arguments = @(
      'sign',
      '/fd', 'SHA256',
      '/f', $certificatePath
    )
    if (-not [string]::IsNullOrEmpty($CertificatePassword)) {
      $arguments += @('/p', $CertificatePassword)
    }
    if (-not [string]::IsNullOrWhiteSpace($TimestampUrl)) {
      $arguments += @('/tr', $TimestampUrl, '/td', 'SHA256')
    }
    $arguments += $target.FullName
    & $signtoolPath @arguments
    if ($LASTEXITCODE -ne 0) {
      throw "signtool failed for $($target.FullName) with exit code $LASTEXITCODE."
    }
  }
} finally {
  Remove-Item -LiteralPath $certificatePath -Force -ErrorAction SilentlyContinue
}

foreach ($target in $targets) {
  $signature = Get-AuthenticodeSignature -LiteralPath $target.FullName
  if ($signature.Status -eq 'NotSigned') {
    throw "Authenticode signature is missing after signing: $($target.FullName)"
  }
}

Write-Host "Signed $($targets.Count) Windows bundle files with Authenticode."
