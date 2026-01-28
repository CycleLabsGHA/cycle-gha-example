<#
install-browsers.ps1 (PowerShell 5.1+)

Modes:
- Default: installs "normal" Chrome via Enterprise MSI (latest), installs ChromeDriver via NuGet (latest if missing),
           EdgeDriver auto-matches installed Edge major (unless -EdgeMajor specified).
- Pinned Chrome major:
    - If -UseChromeForTestingWhenPinned is set: use Chrome for Testing (CfT) + matching ChromeDriver for that major.
    - Else: keep normal MSI Chrome (cannot reliably pin major); warn; install ChromeDriver matching *installed* Chrome major via CfT.
- Edge major:
    - If -EdgeMajor is set: installs EdgeDriver matching that major (latest patch in that major from page scrape).
    - Else: auto-detect installed Edge major and installs matching EdgeDriver.
- Force switches:
    - -ForceDrivers: always refresh drivers even if already present in C:\tools\selenium
    - -ForceBrowsers: always refresh/reinstall Chrome (MSI reinstall; CfT re-download/extract)

Notes:
- This script does NOT attempt to reinstall Microsoft Edge itself (it’s typically managed by Windows / enterprise tooling).
- Exports env vars (when running in GitHub Actions): CHROME_PATH, EDGE_PATH, CHROMEDRIVER_PATH, EDGEDRIVER_PATH
#>

param(
  # null/empty => "latest normal Chrome" (Enterprise MSI)
  [ValidateRange(80, 250)]
  [int]$ChromeMajor,

  # When -ChromeMajor is set, this forces using Chrome for Testing (CfT) to actually pin that major.
  [switch]$UseChromeForTestingWhenPinned,

  # null/empty => auto-detect from installed Edge, else fallback to latest stable EdgeDriver
  [ValidateRange(80, 250)]
  [int]$EdgeMajor,

  # If set, always reinstall/refresh drivers even if executables already exist in C:\tools\selenium
  [switch]$ForceDrivers,

  # If set, always reinstall/refresh Chrome (MSI reinstall; CfT re-download/extract)
  [switch]$ForceBrowsers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Install NuGet
# ----------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -Force
Register-PackageSource -Name MyNuGet -Location https://www.nuget.org/api/v2 -ProviderName NuGet -Trusted -Force


# ----------------------------
# Helpers
# ----------------------------
function Write-Section([string]$t) { Write-Host "`n=== $t ===" }

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
    (Join-Path $env:ProgramFiles $LeafRelativePath),
    (Join-Path ${env:ProgramFiles(x86)} $LeafRelativePath)
  )
  return (Find-FirstExistingPath $cands)
}

function Download-File([string]$Url, [string]$OutPath) {
  $wc = New-Object net.webclient
  $wc.DownloadFile($Url, $OutPath)
}

function Ensure-NuGetProvider {
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..."
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
  }
}

function Get-EdgeMajorFromInstalledEdge([string]$EdgeExePath) {
  if (-not $EdgeExePath -or -not (Test-Path $EdgeExePath)) { return $null }
  $v = (Get-Item $EdgeExePath).VersionInfo.FileVersion
  if (-not $v) { return $null }
  return [int]($v.Split('.')[0])
}

function Get-ChromeMajorFromInstalledChrome([string]$ChromeExePath) {
  if (-not $ChromeExePath -or -not (Test-Path $ChromeExePath)) { return $null }
  $v = (Get-Item $ChromeExePath).VersionInfo.FileVersion
  if (-not $v) { return $null }
  return [int]($v.Split('.')[0])
}

# ----------------------------
# Chrome for Testing helpers (pinned major)
# ----------------------------
function Get-CftVersionForMilestone([int]$Major) {
  $milestoneUrl = "https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone.json"
  $json = Invoke-RestMethod -Uri $milestoneUrl -UseBasicParsing
  $v = $json.milestones."$Major".version
  if (-not $v) { throw "Chrome for Testing: could not find a version for milestone $Major." }
  return $v
}

function Get-CftMetaForVersion([string]$Version) {
  $verUrl = "https://googlechromelabs.github.io/chrome-for-testing/$Version.json"
  return (Invoke-RestMethod -Uri $verUrl -UseBasicParsing)
}

# ----------------------------
# Chrome (normal MSI)
# ----------------------------
function Install-ChromeEnterpriseMsi {
  Write-Section "Install Chrome (latest stable via Enterprise MSI)"

  $chromeExe = Find-InProgramFiles "Google\Chrome\Application\chrome.exe"
  if ($chromeExe -and (-not $ForceBrowsers)) {
    Write-Host "[SKIP] Chrome already present at: $chromeExe"
    return $chromeExe
  }
  if ($chromeExe -and $ForceBrowsers) {
    Write-Host "[FORCE] Reinstalling Chrome (MSI)"
  }

  $url = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
  $msiInstaller = Join-Path $env:TEMP "google-chrome.msi"

  Write-Host "Downloading Google Chrome MSI..."
  Download-File -Url $url -OutPath $msiInstaller

  Write-Host "Installing Google Chrome..."
  $arguments = "/i `"$msiInstaller`" /quiet /norestart"
  Start-Process msiexec.exe -ArgumentList $arguments -Wait -NoNewWindow

  Remove-Item $msiInstaller -Force -ErrorAction SilentlyContinue

  $chromeExe = Find-InProgramFiles "Google\Chrome\Application\chrome.exe"
  if (-not $chromeExe) { throw "Chrome install finished but chrome.exe was not found." }

  Write-Host "[OK] Chrome installed at: $chromeExe"
  return $chromeExe
}

# ----------------------------
# Chrome for Testing (pinned major)
# ----------------------------
function Install-ChromeCftPinnedMajor([int]$Major) {
  Write-Section "Install Chrome (pinned major $Major via Chrome for Testing)"

  $version = Get-CftVersionForMilestone -Major $Major
  Write-Host "[OK] Latest CfT version for M$($Major): $version"

  $meta = Get-CftMetaForVersion -Version $version
  $chromeUrl = ($meta.downloads.chrome | Where-Object { $_.platform -eq "win64" } | Select-Object -First 1).url
  if (-not $chromeUrl) { throw "No win64 Chrome download URL found for $version." }

  $workRoot = Join-Path $env:LOCALAPPDATA "selenium-drivers\cft"
  Ensure-Dir $workRoot

  $extractDir = Join-Path $workRoot "chrome-$version"
  $zipPath    = Join-Path $workRoot "chrome-$version.zip"

  if (Test-Path $extractDir) {
    if ($ForceBrowsers) {
      Write-Host "[FORCE] Reinstalling Chrome for Testing (re-download/extract)"
      Remove-Item $extractDir -Recurse -Force
    } else {
      # If folder exists and not forcing, we can reuse it.
      $existingExe = Get-ChildItem -Path $extractDir -Recurse -Filter chrome.exe -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($existingExe) {
        Write-Host "[SKIP] Chrome for Testing already present at: $($existingExe.FullName)"
        return $existingExe.FullName
      }
      # If exe isn't present, fall through to re-extract
      Remove-Item $extractDir -Recurse -Force
    }
  }
  Ensure-Dir $extractDir

  Write-Host "Downloading Chrome (CfT)..."
  Download-File -Url $chromeUrl -OutPath $zipPath

  Write-Host "Extracting Chrome (CfT)..."
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
  Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

  $exe = Get-ChildItem -Path $extractDir -Recurse -Filter chrome.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { throw "chrome.exe not found after extracting CfT $version." }

  Write-Host "[OK] Chrome (CfT) at: $($exe.FullName)"
  return $exe.FullName
}

# ----------------------------
# ChromeDriver
# ----------------------------
function Install-ChromeDriverLatestNuGet([string]$OutDir) {
  Write-Section "Install ChromeDriver (latest via NuGet)"
  Ensure-NuGetProvider

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

function Install-ChromeDriverCftPinnedMajor([int]$Major, [string]$OutDir) {
  Write-Section "Install ChromeDriver (major $Major via Chrome for Testing)"

  $version = Get-CftVersionForMilestone -Major $Major
  Write-Host "[OK] Latest CfT version for M$($Major): $version"

  $meta = Get-CftMetaForVersion -Version $version
  $driverUrl = ($meta.downloads.chromedriver | Where-Object { $_.platform -eq "win64" } | Select-Object -First 1).url
  if (-not $driverUrl) { throw "No win64 ChromeDriver download URL found for $version." }

  $workRoot = Join-Path $env:LOCALAPPDATA "selenium-drivers\cft"
  Ensure-Dir $workRoot

  $extractDir = Join-Path $workRoot "chromedriver-$version"
  $zipPath    = Join-Path $workRoot "chromedriver-$version.zip"

  if (Test-Path $extractDir) {
    if ($ForceDrivers) {
      Write-Host "[FORCE] Reinstalling ChromeDriver for Testing (re-download/extract)"
      Remove-Item $extractDir -Recurse -Force
    } else {
      $existingExe = Get-ChildItem -Path $extractDir -Recurse -Filter chromedriver.exe -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($existingExe) {
        Copy-Item $existingExe.FullName -Destination $OutDir -Force
        $dst = Join-Path $OutDir "chromedriver.exe"
        Write-Host "[SKIP] ChromeDriver already present (reused) -> $dst"
        return $dst
      }
      Remove-Item $extractDir -Recurse -Force
    }
  }
  Ensure-Dir $extractDir

  Write-Host "Downloading ChromeDriver (CfT)..."
  Download-File -Url $driverUrl -OutPath $zipPath

  Write-Host "Extracting ChromeDriver (CfT)..."
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
  Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

  $exe = Get-ChildItem -Path $extractDir -Recurse -Filter chromedriver.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { throw "chromedriver.exe not found after extracting CfT $version." }

  Copy-Item $exe.FullName -Destination $OutDir -Force
  $dst = Join-Path $OutDir "chromedriver.exe"

  Write-Host "[OK] ChromeDriver copied to: $dst"
  return $dst
}

# ----------------------------
# EdgeDriver
# ----------------------------
function Get-EdgeDriverCandidateLinks {
  $downloadPage = "https://developer.microsoft.com/en-us/microsoft-edge/tools/webdriver?ch=1"
  $html = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing

  $regex = [regex]::new("https://(msedgedriver\.microsoft\.com|msedgedriver\.azureedge\.net)/([0-9\.]+)/edgedriver_win64\.zip")
  $matches = $regex.Matches($html.Content)

  if ($matches.Count -eq 0) { throw "Could not find EdgeDriver links in page HTML." }

  $cands = @()
  foreach ($m in $matches) {
    $cands += [pscustomobject]@{
      Version = $m.Groups[2].Value
      Url     = $m.Value
    }
  }
  return $cands
}

function Install-EdgeDriver([int]$Major, [string]$OutDir) {
  $title = "latest stable"
  if ($Major) { $title = "major $Major" }
  Write-Section "Install EdgeDriver ($title)"

  $cands = Get-EdgeDriverCandidateLinks

  if ($Major) {
    $cands = $cands | Where-Object { $_.Version.StartsWith("$Major.") }
    if (-not $cands -or $cands.Count -eq 0) { throw "No EdgeDriver found for major $Major." }
  }

  $chosen = $cands | Sort-Object Version -Descending | Select-Object -First 1
  Write-Host "[OK] Selected EdgeDriver version: $($chosen.Version)"
  Write-Host "[OK] Download URL: $($chosen.Url)"

  $tempDir = Join-Path $env:TEMP "edge_driver_install"
  Ensure-Dir $tempDir

  $edgeZip = Join-Path $tempDir "edgedriver.zip"
  $extractPath = Join-Path $tempDir "edgedriver"

  if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }

  Invoke-WebRequest -Uri $chosen.Url -OutFile $edgeZip -UseBasicParsing
  Expand-Archive -LiteralPath $edgeZip -DestinationPath $extractPath -Force

  $exe = Get-ChildItem -Path $extractPath -Recurse -Filter msedgedriver.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $exe) { throw "msedgedriver.exe not found after extraction." }

  Copy-Item $exe.FullName -Destination $OutDir -Force
  $dst = Join-Path $OutDir "msedgedriver.exe"

  Write-Host "[OK] EdgeDriver copied to: $dst"

  Remove-Item $edgeZip -Force -ErrorAction SilentlyContinue
  Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

  return $dst
}

# ----------------------------
# Verification / output
# ----------------------------
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

  Write-Host "`nExported env vars (if running in GitHub Actions):"
  Write-Host "  CHROME_PATH, EDGE_PATH, CHROMEDRIVER_PATH, EDGEDRIVER_PATH"
}

# ----------------------------
# Main
# ----------------------------
Write-Section "Setup driver folder"
$seleniumPath = "C:\tools\selenium"
Ensure-Dir $seleniumPath

# --- Chrome ---
$chromeExe = $null
$chromeDriverExe = Join-Path $seleniumPath "chromedriver.exe"

if ($ChromeMajor -and $UseChromeForTestingWhenPinned) {
  # True pin: CfT chrome + matching driver (ForceBrowsers affects CfT reuse)
  $chromeExe = Install-ChromeCftPinnedMajor -Major $ChromeMajor
  # Driver refresh controlled by ForceDrivers
  $chromeDriverExe = Install-ChromeDriverCftPinnedMajor -Major $ChromeMajor -OutDir $seleniumPath
} else {
  # Default: normal Chrome MSI (ForceBrowsers forces reinstall)
  $chromeExe = Install-ChromeEnterpriseMsi

  # If user asked for a major but did NOT allow CfT, warn and match driver to installed Chrome major
  if ($ChromeMajor -and (-not $UseChromeForTestingWhenPinned)) {
    $installedMajor = Get-ChromeMajorFromInstalledChrome -ChromeExePath $chromeExe
    Write-Host "[WARN] -ChromeMajor $ChromeMajor requested, but using normal Chrome (MSI). Installed Chrome major is $installedMajor. Pinning is not enforced."

    if ($installedMajor) {
      $chromeDriverExe = Install-ChromeDriverCftPinnedMajor -Major $installedMajor -OutDir $seleniumPath
    } else {
      $chromeDriverExe = Install-ChromeDriverLatestNuGet -OutDir $seleniumPath
    }
  } else {
    # Latest mode: install/refresh driver
    if ((-not $ForceDrivers) -and (Test-Path $chromeDriverExe)) {
      Write-Host "`n[SKIP] ChromeDriver already present at: $chromeDriverExe"
    } else {
      $chromeDriverExe = Install-ChromeDriverLatestNuGet -OutDir $seleniumPath
    }
  }
}

# --- Edge ---
$edgeExe = Find-InProgramFiles "Microsoft\Edge\Application\msedge.exe"
if ($edgeExe) {
  Write-Host "`n[OK] Edge found at: $edgeExe"
} else {
  Write-Host "`n[WARN] Edge not found (msedge.exe). If you need Edge installed, add an install step."
}

# Resolve Edge major:
# - If user passes -EdgeMajor => use it
# - Else auto-detect installed Edge major
# - Else $null => EdgeDriver falls back to latest stable
$resolvedEdgeMajor = $EdgeMajor
if (-not $resolvedEdgeMajor) {
  $autoMajor = Get-EdgeMajorFromInstalledEdge -EdgeExePath $edgeExe
  if ($autoMajor) {
    $resolvedEdgeMajor = $autoMajor
    Write-Host "[OK] Auto-detected Edge major: $resolvedEdgeMajor"
  } else {
    Write-Host "[WARN] Could not detect Edge major; falling back to latest stable EdgeDriver."
  }
}

# EdgeDriver
$edgeDriverExe = Join-Path $seleniumPath "msedgedriver.exe"
if ((-not $ForceDrivers) -and (Test-Path $edgeDriverExe)) {
  Write-Host "`n[SKIP] EdgeDriver already present at: $edgeDriverExe"
} else {
  $edgeDriverExe = Install-EdgeDriver -Major $resolvedEdgeMajor -OutDir $seleniumPath
}

# Final verification / output
Verify-And-Print -ChromeExe $chromeExe -EdgeExe $edgeExe -ChromeDriverExe $chromeDriverExe -EdgeDriverExe $edgeDriverExe
