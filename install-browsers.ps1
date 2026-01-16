Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section($t) { Write-Host "`n=== $t ===" }

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
}

function Add-GitHubEnvVar([string]$Name, [string]$Value) {
  if ($env:GITHUB_ENV) {
    "$Name=$Value" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
  }
}

function Get-ExeVersion([string]$Path) {
  try { return (Get-Item $Path).VersionInfo.FileVersion } catch { return $null }
}

function Find-FirstExistingPath([string[]]$Candidates) {
  foreach ($p in $Candidates) {
    if ($p -and (Test-Path $p)) { return (Resolve-Path $p).Path }
  }
  return $null
}

function Find-InProgramFiles([string]$LeafRelativePath) {
  $cands = @(
    Join-Path $env:ProgramFiles $LeafRelativePath
    Join-Path ${env:ProgramFiles(x86)} $LeafRelativePath
  )
  return (Find-FirstExistingPath $cands)
}

function Install-ChromeEnterpriseMsi {
  Write-Section "Install Google Chrome (Enterprise MSI)"

  $chromeExe = Find-InProgramFiles "Google\Chrome\Application\chrome.exe"
  if ($chromeExe) {
    Write-Host "[SKIP] Chrome already present at: $chromeExe"
    return $chromeExe
  }

  $url = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
  $msiInstaller = Join-Path $env:TEMP "google-chrome.msi"

  Write-Host "Downloading Google Chrome MSI..."
  (New-Object net.webclient).DownloadFile($url, $msiInstaller)

  Write-Host "Installing Google Chrome..."
  $arguments = "/i `"$msiInstaller`" /quiet /norestart"
  Start-Process msiexec.exe -ArgumentList $arguments -Wait -NoNewWindow

  Remove-Item $msiInstaller -Force -ErrorAction SilentlyContinue

  # Re-check
  $chromeExe = Find-InProgramFiles "Google\Chrome\Application\chrome.exe"
  if (-not $chromeExe) { throw "Chrome install finished but chrome.exe was not found." }

  Write-Host "[OK] Chrome installed at: $chromeExe"
  return $chromeExe
}

function Ensure-NuGetProvider {
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
  }
}

function Install-ChromeDriverFromNuGet([string]$OutDir) {
  Write-Section "Install ChromeDriver (NuGet Selenium.WebDriver.ChromeDriver)"
  Ensure-NuGetProvider

  # Install under a deterministic folder instead of "."
  $pkgRoot = Join-Path $env:LOCALAPPDATA "selenium-drivers\nuget"
  Ensure-Dir $pkgRoot

  $pkg = (Install-Package Selenium.WebDriver.ChromeDriver -Destination $pkgRoot -Force -Scope CurrentUser)[0]
  $pkgPath = Join-Path $pkgRoot "$($pkg.Name).$($pkg.Version)"

  $exe = Get-ChildItem -Path $pkgPath -Recurse -Filter chromedriver.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { throw "ChromeDriver not found under $pkgPath" }

  Copy-Item $exe.FullName -Destination $OutDir -Force
  $dst = Join-Path $OutDir "chromedriver.exe"

  Write-Host "[OK] ChromeDriver copied to: $dst"
  return $dst
}

function Get-LatestEdgeDriverUrlWin64 {
  # Scrape from Microsoft page; handle both msedgedriver domains.
  $downloadPage = "https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver?ch=1"
  $html = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing

  $regex = [regex]::new("https://(msedgedriver\.microsoft\.com|msedgedriver\.azureedge\.net)/([0-9\.]+)/edgedriver_win64\.zip")
  $matches = $regex.Matches($html.Content)

  if ($matches.Count -eq 0) { throw "Could not find EdgeDriver win64 link in page HTML." }

  # Pick the highest version found
  $cands = @()
  foreach ($m in $matches) {
    $cands += [pscustomobject]@{
      Version = $m.Groups[2].Value
      Url     = $m.Value
    }
  }
  $chosen = $cands | Sort-Object Version -Descending | Select-Object -First 1
  return $chosen
}

function Install-EdgeDriver([string]$OutDir) {
  Write-Section "Install EdgeDriver (latest stable)"

  $tempDir = Join-Path $env:TEMP "edge_driver_install"
  Ensure-Dir $tempDir

  $edgeZip = Join-Path $tempDir "edgedriver.zip"
  $extractPath = Join-Path $tempDir "edgedriver"

  if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }

  $chosen = Get-LatestEdgeDriverUrlWin64
  Write-Host "[OK] Selected EdgeDriver version: $($chosen.Version)"
  Write-Host "[OK] Download URL: $($chosen.Url)"

  Write-Host "Downloading EdgeDriver..."
  Invoke-WebRequest -Uri $chosen.Url -OutFile $edgeZip -UseBasicParsing

  Write-Host "Extracting EdgeDriver..."
  Expand-Archive -LiteralPath $edgeZip -DestinationPath $extractPath -Force

  $exe = Get-ChildItem -Path $extractPath -Recurse -Filter msedgedriver.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { throw "msedgedriver.exe not found after extraction." }

  Copy-Item $exe.FullName -Destination $OutDir -Force
  $dst = Join-Path $OutDir "msedgedriver.exe"

  Write-Host "[OK] EdgeDriver copied to: $dst"

  # Cleanup
  Remove-Item $edgeZip -Force -ErrorAction SilentlyContinue
  Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

  return $dst
}

function Verify-And-Print {
  param(
    [string]$ChromeExe,
    [string]$EdgeExe,
    [string]$ChromeDriverExe,
    [string]$EdgeDriverExe
  )

  Write-Section "Verification summary (paths + versions)"

  $items = @(
    @{ Name="Chrome";       Path=$ChromeExe;       Env="CHROME_PATH" },
    @{ Name="Edge";         Path=$EdgeExe;         Env="EDGE_PATH" },
    @{ Name="ChromeDriver"; Path=$ChromeDriverExe; Env="CHROMEDRIVER_PATH" },
    @{ Name="EdgeDriver";   Path=$EdgeDriverExe;   Env="EDGEDRIVER_PATH" }
  )

  foreach ($i in $items) {
    $p = $i.Path
    if (-not $p) {
      Write-Host ("[FAIL] {0}: path not set" -f $i.Name)
      continue
    }
    if (-not (Test-Path $p)) {
      Write-Host ("[FAIL] {0}: not found at {1}" -f $i.Name, $p)
      continue
    }

    $ver = Get-ExeVersion $p
    if ($ver) {
      Write-Host ("[OK]   {0}: {1} (version {2})" -f $i.Name, $p, $ver)
    } else {
      Write-Host ("[OK]   {0}: {1}" -f $i.Name, $p)
    }

    Add-GitHubEnvVar -Name $i.Env -Value $p
  }

  # Extra: emit to logs for easy copy/paste
  Write-Host "`nExported env vars (if running in GitHub Actions):"
  Write-Host "  CHROME_PATH, EDGE_PATH, CHROMEDRIVER_PATH, EDGEDRIVER_PATH"
}

# ----------------------------
# Main
# ----------------------------
$seleniumPath = "C:\tools\selenium"
Ensure-Dir $seleniumPath

# Chrome
$chromeExe = Install-ChromeEnterpriseMsi

# ChromeDriver
$chromeDriverExe = Join-Path $seleniumPath "chromedriver.exe"
if (Test-Path $chromeDriverExe) {
  Write-Host "`n[SKIP] ChromeDriver already present at: $chromeDriverExe"
} else {
  $chromeDriverExe = Install-ChromeDriverFromNuGet -OutDir $seleniumPath
}

# Edge (only verify path; Edge is normally present on Windows)
$edgeExe = Find-InProgramFiles "Microsoft\Edge\Application\msedge.exe"
if (-not $edgeExe) {
  # fallback: try command resolution
  $cmd = Get-Command msedge -ErrorAction SilentlyContinue
  if ($cmd) { $edgeExe = $cmd.Source }
}

if ($edgeExe) {
  Write-Host "`n[OK] Edge found at: $edgeExe"
} else {
  Write-Host "`n[WARN] Edge not found (msedge.exe). If you need Edge installed, add an install step."
}

# EdgeDriver
$edgeDriverExe = Join-Path $seleniumPath "msedgedriver.exe"
if (Test-Path $edgeDriverExe) {
  Write-Host "`n[SKIP] EdgeDriver already present at: $edgeDriverExe"
} else {
  $edgeDriverExe = Install-EdgeDriver -OutDir $seleniumPath
}

# Verify / Print
Verify-And-Print -ChromeExe $chromeExe -EdgeExe $edgeExe -ChromeDriverExe $chromeDriverExe -EdgeDriverExe $edgeDriverExe
