#Requires -Version 5.1
# MCS Deployment Script
# This script builds and deploys both WebAPI and Angular/Ionic projects to FTP
# Now supports cloning from Git, cleaning up local files, and separate FTP credentials.
# Headless mode: Configuration is read solely from deploy-config.json.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Dev", "Test", "Prod")]
    [string]$Environment
)

# Configuration file path
$configFile = Join-Path $PSScriptRoot "deploy-config.json"

# Load configuration
function Load-Config {
    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
            return $config
        }
        catch {
            Write-Warning "Error loading config file: $_"
            return $null
        }
    }
    return $null
}

# Clone Repository
function Clone-Repo {
    param(
        [string]$RepoUrl,
        [string]$Branch,
        [string]$TargetDir
    )

    Write-Host "`n=== Cloning Repository ===" -ForegroundColor Cyan
    Write-Host "Repo: $RepoUrl" -ForegroundColor Gray
    Write-Host "Branch: $Branch" -ForegroundColor Gray
    Write-Host "Target: $TargetDir" -ForegroundColor Gray

    if (Test-Path $TargetDir) {
        Write-Host "Removing existing target directory: $TargetDir" -ForegroundColor Yellow
        Remove-Directory -TargetDir $TargetDir
    }

    try {
        Write-Host "Git cloning..." -ForegroundColor Yellow
        # Use cmd /c to prevent PowerShell from treating git's stderr progress output as a script error
        & cmd /c "git clone -b $Branch $RepoUrl $TargetDir"
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $TargetDir)) {
            Write-Host "Clone successful" -ForegroundColor Green
            return $true
        }
        else {
            Write-Error "Git clone failed. Ensure Git is installed and credentials are correct."
            return $false
        }
    }
    catch {
        Write-Error "Error during git clone: $_"
        return $false
    }
}

# Remove Directory
function Remove-Directory {
    param(
        [string]$TargetDir
    )
    
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

# Build WebAPI project
function Build-WebAPI {
    param(
        [string]$ApiPath
    )
    
    Write-Host "`n=== Building WebAPI Project ===" -ForegroundColor Cyan
    Write-Host "Project Path: $ApiPath" -ForegroundColor Gray
    
    if (-not (Test-Path $ApiPath)) {
        Write-Error "WebAPI project path does not exist: $ApiPath"
        return $null
    }
    
    # Find .csproj or .sln file
    $csproj = Get-ChildItem -Path $ApiPath -Filter "*.csproj" -Recurse | Select-Object -First 1
    $sln = Get-ChildItem -Path $ApiPath -Filter "*.sln" -Recurse | Select-Object -First 1
    
    if (-not $csproj -and -not $sln) {
        Write-Error "No .csproj or .sln file found in $ApiPath"
        Write-Host "Contents of $ApiPath :" -ForegroundColor Yellow
        Get-ChildItem -Path $ApiPath | Format-Table Name, Attributes -AutoSize | Out-String | Write-Host
        return $null
    }
    
    $buildTarget = if ($sln) { $sln.FullName } else { $csproj.FullName }
    
    Write-Host "Building: $buildTarget" -ForegroundColor Yellow
    
    # Build with dotnet or msbuild
    $dotnetPath = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnetPath) {
        Push-Location $ApiPath
        try {
            # Restore first
            dotnet restore $buildTarget 2>&1 | Out-Host
            
            # Publish (better than build for deployment)
            $publishDir = Join-Path $ApiPath "bin\Publish"
            if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
            
            & dotnet publish $buildTarget --configuration Release --output $publishDir 2>&1 | Out-Host
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "WebAPI publish successful" -ForegroundColor Green
                Write-Host "Publish output: $publishDir" -ForegroundColor Green
                return $publishDir
            }
            else {
                Write-Error "WebAPI build failed"
                return $null
            }
        }
        catch {
            Write-Error "Error during build: $_"
            return $null
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Error "dotnet SDK not found. Please install .NET Core SDK."
        return $null
    }
}

# Build Angular/Ionic project
function Build-Angular {
    param(
        [string]$UiPath
    )
    
    Write-Host "`n=== Building Angular/Ionic Project ===" -ForegroundColor Cyan
    Write-Host "Project Path: $UiPath" -ForegroundColor Gray
    
    if (-not (Test-Path $UiPath)) {
        Write-Error "UI project path does not exist: $UiPath"
        return $null
    }
    
    Push-Location $UiPath
    try {
        # Check if node_modules exists
        if (-not (Test-Path "node_modules")) {
            Write-Host "Installing npm dependencies..." -ForegroundColor Yellow
            & npm install | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Error "npm install failed"
                return $null
            }
        }
        
        # Build for production
        Write-Host "Building Angular project for production..." -ForegroundColor Yellow
        & npm run build:prod | Out-Host
        if ($LASTEXITCODE -ne 0) {
            # Fallback to standard build if build:prod not found, or error? 
            # Let's try just build
            Write-Warning "'npm run build:prod' failed. Trying 'npm run build'..."
            & npm run build | Out-Host
        }

        if ($LASTEXITCODE -eq 0) {
            $wwwPath = Join-Path $UiPath "www"
            if (Test-Path $wwwPath) {
                Write-Host "Angular build successful" -ForegroundColor Green
                
                # Rename index.prod.html to index.html
                $indexProd = Join-Path $wwwPath "index.prod.html"
                $index = Join-Path $wwwPath "index.html"
                if (Test-Path $indexProd) {
                    if (Test-Path $index) { Remove-Item $index -Force }
                    Rename-Item -Path $indexProd -NewName "index.html"
                    Write-Host "Renamed index.prod.html to index.html" -ForegroundColor Gray
                }

                # Create web.config for IIS Rewrites
                $webConfigContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="Angular Routes" stopProcessing="true">
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
                $webConfigPath = Join-Path $wwwPath "web.config"
                Set-Content -Path $webConfigPath -Value $webConfigContent -Encoding UTF8
                Write-Host "Created web.config for IIS" -ForegroundColor Gray

                Write-Host "Build output: $wwwPath" -ForegroundColor Green
                return $wwwPath
            }
            else {
                Write-Error "www folder not found after build"
                return $null
            }
        }
        else {
            Write-Error "Angular build failed"
            return $null
        }
    }
    catch {
        Write-Error "Error during Angular build: $_"
        return $null
    }
    finally {
        Pop-Location
    }
}

# Create FTP directory
function Create-FtpDirectory {
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
        # Directory might already exist, which is fine
        return $false
    }
}

# Upload to FTP
function Upload-ToFtp {
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
    
    # Ensure FTP path starts with /
    if (-not $FtpPath.StartsWith("/")) {
        $FtpPath = "/" + $FtpPath
    }
    
    # Remove trailing slash from FTP server
    $FtpServer = $FtpServer.TrimEnd('/')
    
    try {
        # Create base FTP directory if needed
        $baseFtpUri = "$FtpServer$FtpPath"
        Create-FtpDirectory -FtpUri $baseFtpUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null
        
        Write-Host "Uploading to: $baseFtpUri" -ForegroundColor Yellow
        
        # Get all files and directories
        $items = Get-ChildItem -Path $LocalPath -Recurse
        $files = $items | Where-Object { -not $_.PSIsContainer }
        $directories = $items | Where-Object { $_.PSIsContainer }
        
        $totalFiles = $files.Count
        $currentFile = 0
        $uploadErrors = 0
        
        # Create directories first
        foreach ($dir in $directories) {
            $relativePath = $dir.FullName.Substring($LocalPath.Length).Replace('\', '/').TrimStart('/')
            if (-not [string]::IsNullOrEmpty($relativePath)) {
                $ftpDirUri = "$baseFtpUri/$relativePath"
                Create-FtpDirectory -FtpUri $ftpDirUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null
            }
        }
        
        # Upload files
        foreach ($file in $files) {
            $currentFile++
            $relativePath = $file.FullName.Substring($LocalPath.Length).Replace('\', '/').TrimStart('/')
            $ftpFileUri = "$baseFtpUri/$relativePath"
            
            Write-Progress -Activity "Uploading to FTP" -Status "Uploading $relativePath" -PercentComplete (($currentFile / $totalFiles) * 100)
            
            try {
                # Ensure parent directory exists (double check for nested deep paths)
                $parentDir = Split-Path $relativePath -Parent
                if ($parentDir) {
                    $parentFtpUri = "$baseFtpUri/$parentDir".Replace('\', '/')
                    # Attempt create just in case
                    # Create-FtpDirectory -FtpUri $parentFtpUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null
                }
                
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
        else {
            Write-Warning "FTP upload completed with $uploadErrors errors out of $totalFiles files"
            return $false
        }
    }
    catch {
        Write-Error "FTP upload failed: $_"
        return $false
    }
}

# Clear FTP Directory
function Clear-FtpDirectory {
    param(
        [string]$FtpUri,
        [string]$FtpUser,
        [string]$FtpPassword
    )

    Write-Host "Clearing FTP directory: $FtpUri" -ForegroundColor Yellow

    try {
        # Ensure URI ends with /
        if (-not $FtpUri.EndsWith("/")) { $FtpUri += "/" }

        $ftpRequest = [System.Net.FtpWebRequest]::Create($FtpUri)
        $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
        $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $ftpRequest.UsePassive = $true

        $response = $ftpRequest.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $content = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()

        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Host "  Directory is empty." -ForegroundColor Gray
            return $true
        }

        # Parse listing (Unix/Windows format varies, simple line parsing usually works for names if careful)
        # This simple parser assumes standard Unix-style output or Windows style which has details.
        # A more robust way using ListDirectory (names only) is often safer for deletion loops.
        
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
            # Trim to handle potential odd whitespace
            $itemName = $item.Trim()
            # Skip . and ..
            if ($itemName -eq "." -or $itemName -eq "..") { continue }

            $itemUri = "$FtpUri$itemName"
            
            # Try to delete as file first
            try {
                $delRequest = [System.Net.FtpWebRequest]::Create($itemUri)
                $delRequest.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $FtpPassword)
                $delRequest.Method = [System.Net.WebRequestMethods+Ftp]::DeleteFile
                $delRequest.UsePassive = $true
                $delRequest.GetResponse().Close()
                Write-Host "  Deleted file: $itemName" -ForegroundColor Gray
            }
            catch {
                # If failed, assume it might be a directory and try recursive delete + remove dir
                try {
                    # Recursively clear sub-directory
                    Clear-FtpDirectory -FtpUri "$itemUri/" -FtpUser $FtpUser -FtpPassword $FtpPassword
                    
                    # Remove the now-empty directory
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


# Main deployment function
function Start-Deployment {
    param([string]$Environment)

    Write-Host "Loading configuration for $Environment..." -ForegroundColor Gray
    $fullConfig = Load-Config
    
    if (-not $fullConfig) {
        Write-Error "Configuration could not be loaded. Please ensure 'deploy-config.json' exists and is valid."
        return
    }

    $envConfig = $fullConfig.$Environment
    if (-not $envConfig) {
        Write-Error "Environment '$Environment' not found in configuration."
        return
    }

    # Map nested config to flat structure expected by the script
    $config = [PSCustomObject]@{
        ApiRepoUrl      = $envConfig.Api.RepoUrl
        ApiBranch       = $envConfig.Api.Branch
        ApiFtpUser      = $envConfig.Api.FtpUser
        ApiFtpPassword  = $envConfig.Api.FtpPassword
        ApiFtpPath      = $envConfig.Api.FtpPath
        ApiFtpServer    = $envConfig.Api.FtpServer

        UiRepoUrl       = $envConfig.Ui.RepoUrl
        UiBranch        = $envConfig.Ui.Branch
        UiFtpUser       = $envConfig.Ui.FtpUser
        UiFtpPassword   = $envConfig.Ui.FtpPassword
        UiFtpPath       = $envConfig.Ui.FtpPath
        UiFtpServer     = $envConfig.Ui.FtpServer
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   MCS Deployment Started" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $errors = @()
    $baseTempDir = Join-Path $PSScriptRoot "_temp_deploy"
    if (-not (Test-Path $baseTempDir)) { New-Item -ItemType Directory -Path $baseTempDir | Out-Null }

    # --- API Deployment ---
    if (-not [string]::IsNullOrWhiteSpace($config.ApiRepoUrl)) {
        if ([string]::IsNullOrWhiteSpace($config.ApiFtpServer) -or 
            [string]::IsNullOrWhiteSpace($config.ApiFtpUser) -or 
            [string]::IsNullOrWhiteSpace($config.ApiFtpPassword)) {
            Write-Error "API FTP Credentials are required."
            $errors += "Missing API FTP Credentials"
        }
        else {
            $apiTempDir = Join-Path $baseTempDir "api"
            $apiFtpPath = if ([string]::IsNullOrWhiteSpace($config.ApiFtpPath)) { "/" } else { $config.ApiFtpPath }
            
            if (Clone-Repo -RepoUrl $config.ApiRepoUrl -Branch $config.ApiBranch -TargetDir $apiTempDir) {
                $releasePath = Build-WebAPI -ApiPath $apiTempDir
                if ($releasePath) {
                    Write-Host "Uploading WebAPI to FTP... $releasePath" -ForegroundColor Yellow

                    # Clear FTP before upload
                    Clear-FtpDirectory -FtpUri "$($config.ApiFtpServer)$apiFtpPath" -FtpUser $config.ApiFtpUser -FtpPassword $config.ApiFtpPassword

                    $uploadResult = Upload-ToFtp -LocalPath $releasePath -FtpServer $config.ApiFtpServer -FtpUser $config.ApiFtpUser -FtpPassword $config.ApiFtpPassword -FtpPath $apiFtpPath
                    if (-not $uploadResult) { $errors += "WebAPI deployment failed" }
                }
                else {
                    $errors += "WebAPI build failed"
                }
                # Cleanup API
                Remove-Directory -TargetDir $apiTempDir
            }
            else {
                $errors += "WebAPI Git clone failed"
            }
        }
    }
    
    # --- UI Deployment ---
    if (-not [string]::IsNullOrWhiteSpace($config.UiRepoUrl)) {
        if ([string]::IsNullOrWhiteSpace($config.UiFtpServer) -or 
            [string]::IsNullOrWhiteSpace($config.UiFtpUser) -or 
            [string]::IsNullOrWhiteSpace($config.UiFtpPassword)) {
            Write-Error "UI FTP Credentials are required."
            $errors += "Missing UI FTP Credentials"
        }
        else {
            $uiTempDir = Join-Path $baseTempDir "ui"
            $uiFtpPath = if ([string]::IsNullOrWhiteSpace($config.UiFtpPath)) { "/" } else { $config.UiFtpPath }
            
            if (Clone-Repo -RepoUrl $config.UiRepoUrl -Branch $config.UiBranch -TargetDir $uiTempDir) {
                $wwwPath = Build-Angular -UiPath $uiTempDir
                if ($wwwPath) {
                    # Clear FTP before upload
                    Clear-FtpDirectory -FtpUri "$($config.UiFtpServer)$uiFtpPath" -FtpUser $config.UiFtpUser -FtpPassword $config.UiFtpPassword

                    $uploadResult = Upload-ToFtp -LocalPath $wwwPath -FtpServer $config.UiFtpServer -FtpUser $config.UiFtpUser -FtpPassword $config.UiFtpPassword -FtpPath $uiFtpPath
                    if (-not $uploadResult) { $errors += "UI deployment failed" }
                }
                else {
                    $errors += "Angular build failed"
                }
                # Cleanup UI
                Remove-Directory -TargetDir $uiTempDir
            }
            else {
                $errors += "Angular Git clone failed"
            }
        }
    }
    
    # Cleanup Base Temp
    Remove-Directory -TargetDir $baseTempDir

    # Summary
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

# Run deployment
Start-Deployment -Environment $Environment
