param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BundlePath -PathType Container)) {
  throw "Windows bundle was not found: $BundlePath"
}

$root = Join-Path ([IO.Path]::GetTempPath()) "showrunner-sign-test-$([guid]::NewGuid().ToString('N'))"
$testBundle = Join-Path $root 'bundle'
$pfxPath = Join-Path $root 'test-signing.pfx'
$passwordText = 'showrunner-local-sign-test'
$password = ConvertTo-SecureString $passwordText -AsPlainText -Force
$certificate = $null

try {
  New-Item -ItemType Directory -Force -Path $testBundle | Out-Null
  Copy-Item -LiteralPath (Join-Path $BundlePath 'showrunner_flutter.exe') -Destination $testBundle

  $certificate = New-SelfSignedCertificate `
    -Subject 'CN=ShowRunner local signing test' `
    -Type CodeSigningCert `
    -CertStoreLocation 'Cert:\CurrentUser\My'
  Export-PfxCertificate -Cert $certificate -FilePath $pfxPath -Password $password | Out-Null
  $certificateBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))

  & (Join-Path $PSScriptRoot 'sign-flutter-windows.ps1') `
    -BundlePath $testBundle `
    -CertificateBase64 $certificateBase64 `
    -CertificatePassword $passwordText
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $testBundle 'showrunner_flutter.exe')
  if ($signature.Status -eq 'NotSigned') {
    throw 'The self-signed Windows signing proof did not produce an Authenticode signature.'
  }
  Write-Host "Windows signing proof passed with status $($signature.Status)."
} finally {
  if ($certificate) {
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
