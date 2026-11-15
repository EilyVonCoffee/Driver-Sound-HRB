[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    throw 'keytool was not found. Install a JDK and make sure keytool is on PATH.'
}

$documentsPath = [Environment]::GetFolderPath('MyDocuments')
$keyDirectory = Join-Path $documentsPath 'IEMDriver-keys'
$keystorePath = Join-Path $keyDirectory 'IEMDriver-release.jks'
$keyAlias = 'iemdriverrelease'

if (Test-Path -LiteralPath $keystorePath) {
    throw "Refusing to overwrite existing signing key: $keystorePath"
}

New-Item -ItemType Directory -Path $keyDirectory -Force | Out-Null

Write-Host 'Creating the IEM Driver Android release key.'
Write-Host 'Enter a strong, unique keystore password at the keytool prompt; never paste it into chat.'
Write-Host 'When asked for the key password, press Enter to reuse the keystore password.'

& $keytool.Source -genkeypair -v `
    -keystore $keystorePath `
    -alias $keyAlias `
    -keyalg RSA `
    -keysize 4096 `
    -validity 10000 `
    -dname 'CN=IEM Driver, OU=Release, O=Driver-Sound-HRB, C=ID' `
    -noprompt

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed with exit code $LASTEXITCODE. No release key was confirmed."
}

if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    throw "keytool completed but the keystore was not found at $keystorePath"
}

Write-Host ''
Write-Host "Release keystore created: $keystorePath"
Write-Host "Alias: $keyAlias"
Write-Host 'Back up this file securely before publishing. Losing it can prevent signing compatible Android updates.'
Write-Host ''
Write-Host 'Next: add GitHub Actions secrets IEM_RELEASE_KEYSTORE_BASE64, IEM_RELEASE_STORE_PASSWORD,'
Write-Host 'IEM_RELEASE_KEY_ALIAS, and IEM_RELEASE_KEY_PASSWORD in the repository settings.'
Write-Host 'Use the same password for store/key if you pressed Enter at the key-password prompt.'
Write-Host 'Do not add the keystore or passwords to Git.'
Write-Host ''
Write-Host 'To pipe the base64 keystore directly into GitHub CLI without writing a .base64 file:'
Write-Host "[Convert]::ToBase64String([IO.File]::ReadAllBytes('$keystorePath')) | gh secret set IEM_RELEASE_KEYSTORE_BASE64"
