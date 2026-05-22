#Requires -Version 5.1
# Dinspire Site Deployment Script
# Builds and deploys the Dinspire website (React/Vite or CRA) to FTP.
# Configuration: deploy-dinspire-config.json

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Dev", "Prod")]
    [string]$Environment
)

$configFile = Join-Path $PSScriptRoot "deploy-dinspire-config.json"

function Load-DinspireConfig {
    if (-not (Test-Path $configFile)) {
        Write-Error "Config file not found: $configFile"
        return $null
    }
    try {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Error loading config file: $_"
        return $null
    }
}

function Remove-DeployDirectory {
    param([string]$TargetDir)

    if (Test-Path $TargetDir) {
        try {
            Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction Stop
            Write-Host "Cleaned up: $TargetDir" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Could not fully remove directory: $TargetDir. $_"
            return $false
        }
    }
    return $true
}

function Clone-DinspireRepo {
    param(
        [string]$RepoUrl,
        [string]$Branch,
        [string]$TargetDir
    )

    if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
        Write-Error "Ui.RepoUrl is empty in deploy-dinspire-config.json for $Environment."
        return $false
    }

    Write-Host "`n=== Cloning Repository ===" -ForegroundColor Cyan
    Write-Host "Repo: $RepoUrl" -ForegroundColor Gray
    Write-Host "Branch: $Branch" -ForegroundColor Gray
    Write-Host "Target: $TargetDir" -ForegroundColor Gray

    if (Test-Path $TargetDir) {
        Write-Host "Removing existing target directory: $TargetDir" -ForegroundColor Yellow
        Remove-DeployDirectory -TargetDir $TargetDir | Out-Null
    }

    try {
        Write-Host "Git cloning..." -ForegroundColor Yellow
        if ($IsWindows) {
            & cmd /c "git clone -b $Branch $RepoUrl $TargetDir"
        }
        else {
            & git clone -b $Branch $RepoUrl $TargetDir 2>&1 | Out-Host
        }

        if ($LASTEXITCODE -eq 0 -and (Test-Path $TargetDir)) {
            Write-Host "Clone successful" -ForegroundColor Green
            return $true
        }
        Write-Error "Git clone failed. Ensure Git is installed and credentials are correct."
        return $false
    }
    catch {
        Write-Error "Error during git clone: $_"
        return $false
    }
}

function Build-DinspireSite {
    param(
        [string]$UiPath,
        [string]$Environment
    )

    Write-Host "`n=== Building Dinspire Site ===" -ForegroundColor Cyan
    Write-Host "Project Path: $UiPath" -ForegroundColor Gray

    if (-not (Test-Path $UiPath)) {
        Write-Error "UI project path does not exist: $UiPath"
        return $null
    }

    Push-Location $UiPath
    try {
        $sourceEnvFile = switch ($Environment) {
            "Dev"  { ".env.development" }
            "Prod" { ".env.production" }
            Default { ".env.production" }
        }
        foreach ($overrideFile in @(".env.production.local", ".env.local")) {
            if (Test-Path $overrideFile) {
                Write-Host "Removing $overrideFile so $sourceEnvFile wins for this build..." -ForegroundColor Yellow
                Remove-Item $overrideFile -Force
            }
        }
        if (Test-Path $sourceEnvFile) {
            foreach ($targetEnvFile in @(".env", ".env.production")) {
                if ($sourceEnvFile -eq $targetEnvFile) { continue }
                Write-Host "Using $sourceEnvFile for $Environment (copying to $targetEnvFile)..." -ForegroundColor Yellow
                Copy-Item $sourceEnvFile $targetEnvFile -Force
            }
        }
        else {
            Write-Warning "$sourceEnvFile not found; continuing with existing environment configuration."
        }

        if (-not (Test-Path "node_modules")) {
            Write-Host "Installing npm dependencies..." -ForegroundColor Yellow
            & npm install 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Error "npm install failed"
                return $null
            }
        }

        $envArg = switch ($Environment) {
            "Dev"  { "development" }
            "Prod" { "production" }
            Default { "production" }
        }
        $env:REACT_APP_ENV = $envArg
        Write-Host "Building for $Environment (REACT_APP_ENV=$envArg)..." -ForegroundColor Yellow
        & npm run build 2>&1 | Out-Host
        Remove-Item Env:\REACT_APP_ENV -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Build failed"
            return $null
        }

        $buildPath = $null
        if (Test-Path (Join-Path $UiPath "build")) {
            $buildPath = Join-Path $UiPath "build"
        }
        elseif (Test-Path (Join-Path $UiPath "dist")) {
            $buildPath = Join-Path $UiPath "dist"
        }

        if (-not $buildPath) {
            Write-Error "Build output not found (expected build/ or dist/)"
            return $null
        }

        Write-Host "Build successful: $buildPath" -ForegroundColor Green

        $webConfigContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <modules>
      <remove name="WebDAVModule" />
    </modules>
    <handlers>
      <remove name="WebDAV" />
    </handlers>
    <rewrite>
      <rules>
        <rule name="SPA" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
          </conditions>
          <action type="Rewrite" url="/index.html" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
"@
        Set-Content -Path (Join-Path $buildPath "web.config") -Value $webConfigContent -Encoding UTF8
        Write-Host "Created web.config for IIS" -ForegroundColor Gray

        return $buildPath
    }
    catch {
        Write-Error "Error during build: $_"
        return $null
    }
    finally {
        Pop-Location
    }
}

function New-FtpDirectory {
    param(
        [string]$FtpUri,
        [string]$FtpUser,
        [string]$FtpPassword
    )
    try {
        $ftpRequest = [System.Net.FtpWebRequest]::Create($FtpUri)
        $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
        $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $ftpRequest.UsePassive = $true
        $response = $ftpRequest.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Clear-FtpDirectory {
    param(
        [string]$FtpUri,
        [string]$FtpUser,
        [string]$FtpPassword
    )

    Write-Host "Clearing FTP directory: $FtpUri" -ForegroundColor Yellow

    try {
        if (-not $FtpUri.EndsWith("/")) { $FtpUri += "/" }

        $ftpRequestList = [System.Net.FtpWebRequest]::Create($FtpUri)
        $ftpRequestList.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
        $ftpRequestList.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $ftpRequestList.UsePassive = $true

        $responseList = $ftpRequestList.GetResponse()
        $readerList = New-Object System.IO.StreamReader($responseList.GetResponseStream())
        $fileList = $readerList.ReadToEnd() -split "`r`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $readerList.Close()
        $responseList.Close()

        foreach ($item in $fileList) {
            $itemName = $item.Trim()
            if ($itemName -eq "." -or $itemName -eq "..") { continue }

            $itemUri = "$FtpUri$itemName"
            try {
                $delRequest = [System.Net.FtpWebRequest]::Create($itemUri)
                $delRequest.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
                $delRequest.Method = [System.Net.WebRequestMethods+Ftp]::DeleteFile
                $delRequest.UsePassive = $true
                $delRequest.GetResponse().Close()
                Write-Host "  Deleted file: $itemName" -ForegroundColor Gray
            }
            catch {
                try {
                    Clear-FtpDirectory -FtpUri "$itemUri/" -FtpUser $FtpUser -FtpPassword $FtpPassword
                    $rmDirRequest = [System.Net.FtpWebRequest]::Create($itemUri)
                    $rmDirRequest.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
                    $rmDirRequest.Method = [System.Net.WebRequestMethods+Ftp]::RemoveDirectory
                    $rmDirRequest.UsePassive = $true
                    $rmDirRequest.GetResponse().Close()
                    Write-Host "  Removed directory: $itemName" -ForegroundColor Gray
                }
                catch {
                    Write-Warning "  Failed to delete $itemName : $_"
                }
            }
        }
        return $true
    }
    catch {
        Write-Warning "Error clearing FTP directory $FtpUri : $_"
        return $false
    }
}

function Send-ToFtp {
    param(
        [string]$LocalPath,
        [string]$FtpServer,
        [string]$FtpUser,
        [string]$FtpPassword,
        [string]$FtpPath = "/"
    )

    Write-Host "`n=== Uploading to FTP ===" -ForegroundColor Cyan
    Write-Host "Local Path: $LocalPath" -ForegroundColor Gray
    Write-Host "FTP Server: $FtpServer" -ForegroundColor Gray
    Write-Host "FTP Path: $FtpPath" -ForegroundColor Gray

    if (-not (Test-Path $LocalPath)) {
        Write-Error "Local path does not exist: $LocalPath"
        return $false
    }

    if (-not $FtpPath.StartsWith("/")) { $FtpPath = "/" + $FtpPath }
    $FtpServer = $FtpServer.TrimEnd('/')

    try {
        $baseFtpUri = "$FtpServer$FtpPath"
        New-FtpDirectory -FtpUri $baseFtpUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null

        $items = Get-ChildItem -Path $LocalPath -Recurse
        $files = $items | Where-Object { -not $_.PSIsContainer }
        $directories = $items | Where-Object { $_.PSIsContainer }

        $totalFiles = $files.Count
        $currentFile = 0
        $uploadErrors = 0

        foreach ($dir in $directories) {
            $relativePath = $dir.FullName.Substring($LocalPath.Length).Replace('\', '/').TrimStart('/')
            if (-not [string]::IsNullOrEmpty($relativePath)) {
                $ftpDirUri = "$baseFtpUri/$relativePath"
                New-FtpDirectory -FtpUri $ftpDirUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null
            }
        }

        foreach ($file in $files) {
            $currentFile++
            $relativePath = $file.FullName.Substring($LocalPath.Length).Replace('\', '/').TrimStart('/')
            $ftpFileUri = "$baseFtpUri/$relativePath"

            Write-Progress -Activity "Uploading to FTP" -Status "Uploading $relativePath" -PercentComplete (($currentFile / $totalFiles) * 100)

            try {
                $ftpRequest = [System.Net.FtpWebRequest]::Create($ftpFileUri)
                $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
                $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
                $ftpRequest.UseBinary = $true
                $ftpRequest.UsePassive = $true

                $fileContent = [System.IO.File]::ReadAllBytes($file.FullName)
                $ftpRequest.ContentLength = $fileContent.Length

                $requestStream = $ftpRequest.GetRequestStream()
                $requestStream.Write($fileContent, 0, $fileContent.Length)
                $requestStream.Close()

                $response = $ftpRequest.GetResponse()
                $response.Close()

                Write-Host "  Uploaded: $relativePath" -ForegroundColor Green
            }
            catch {
                $uploadErrors++
                Write-Warning "  Failed to upload: $relativePath - $_"
            }
        }

        Write-Progress -Activity "Uploading to FTP" -Completed

        if ($uploadErrors -eq 0) {
            Write-Host "FTP upload completed successfully ($totalFiles files)" -ForegroundColor Green
            return $true
        }
        Write-Warning "FTP upload completed with $uploadErrors errors out of $totalFiles files"
        return $false
    }
    catch {
        Write-Error "FTP upload failed: $_"
        return $false
    }
}

function Start-DinspireDeployment {
    param([string]$Environment)

    $fullConfig = Load-DinspireConfig
    if (-not $fullConfig) { return }

    $envConfig = $fullConfig.$Environment
    if (-not $envConfig) {
        Write-Error "Environment '$Environment' not found in deploy-dinspire-config.json."
        return
    }

    if (-not $envConfig.Ui) {
        Write-Error "Ui section missing for environment '$Environment'."
        return
    }

    $ui = $envConfig.Ui

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   Dinspire Site Deployment" -ForegroundColor Cyan
    Write-Host "   Environment: $Environment" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($ui.FtpServer) -or
        [string]::IsNullOrWhiteSpace($ui.FtpUser) -or
        [string]::IsNullOrWhiteSpace($ui.FtpPassword)) {
        Write-Error "Ui FTP credentials are required in deploy-dinspire-config.json."
        return
    }

    $errors = @()
    $baseTempDir = Join-Path $PSScriptRoot "_temp_deploy_dinspire"
    if (-not (Test-Path $baseTempDir)) { New-Item -ItemType Directory -Path $baseTempDir | Out-Null }

    $uiTempDir = Join-Path $baseTempDir "ui"
    $uiFtpPath = if ([string]::IsNullOrWhiteSpace($ui.FtpPath)) { "/" } else { $ui.FtpPath }
    $branch = if ([string]::IsNullOrWhiteSpace($ui.Branch)) { "main" } else { $ui.Branch }

    if (Clone-DinspireRepo -RepoUrl $ui.RepoUrl -Branch $branch -TargetDir $uiTempDir) {
        $wwwPath = Build-DinspireSite -UiPath $uiTempDir -Environment $Environment
        if ($wwwPath) {
            Clear-FtpDirectory -FtpUri "$($ui.FtpServer)$uiFtpPath" -FtpUser $ui.FtpUser -FtpPassword $ui.FtpPassword
            $uploadResult = Send-ToFtp -LocalPath $wwwPath -FtpServer $ui.FtpServer -FtpUser $ui.FtpUser -FtpPassword $ui.FtpPassword -FtpPath $uiFtpPath
            if (-not $uploadResult) { $errors += "UI deployment failed" }
        }
        else {
            $errors += "Site build failed"
        }
        Remove-DeployDirectory -TargetDir $uiTempDir
    }
    else {
        $errors += "Git clone failed"
    }

    Remove-DeployDirectory -TargetDir $baseTempDir

    Write-Host "`n========================================" -ForegroundColor Cyan
    if ($errors.Count -eq 0) {
        Write-Host "   Deployment Completed Successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "   Deployment Completed with Errors:" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "   - $err" -ForegroundColor Red
        }
    }
    Write-Host "========================================`n" -ForegroundColor Cyan
}

Start-DinspireDeployment -Environment $Environment
