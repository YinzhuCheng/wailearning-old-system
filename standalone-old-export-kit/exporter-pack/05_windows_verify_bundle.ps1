param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath,
    [string]$Sha256File,
    [string]$ExpectedSha256
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BundlePath)) {
    throw "找不到迁移包：$BundlePath"
}

$bundleItem = Get-Item -LiteralPath $BundlePath
if ($bundleItem.Length -le 0) {
    throw "迁移包大小为 0：$BundlePath"
}

$hash = (Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = $null

if ($Sha256File) {
    if (-not (Test-Path -LiteralPath $Sha256File)) {
        throw "找不到 SHA256 文件：$Sha256File"
    }
    $shaLine = (Get-Content -LiteralPath $Sha256File | Select-Object -First 1).Trim()
    if (-not $shaLine) {
        throw "SHA256 文件为空：$Sha256File"
    }
    $expected = (($shaLine -split '\s+')[0]).ToLowerInvariant()
}

if ($ExpectedSha256) {
    $expected = $ExpectedSha256.ToLowerInvariant()
}

if ($expected -and $hash -ne $expected) {
    throw "SHA256 不匹配。实际：$hash 期望：$expected"
}

$tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tarCommand) {
    & $tarCommand.Source -tf $BundlePath | Out-Null
}

Write-Host "校验通过。"
Write-Host "文件：" $BundlePath
Write-Host "大小：" $bundleItem.Length "bytes"
Write-Host "SHA256：" $hash
