#Requires -Version 5.1
# MCS Deployment Script
# This script builds and deploys both WebAPI and Angular/Ionic projects to FTP
# Now supports cloning from Git, cleaning up local files, and separate FTP credentials.
# Headless mode: Configuration is read solely from deploy-config.json.

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
        git clone -b $Branch $RepoUrl $TargetDir
        
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
            dotnet restore $buildTarget
            
            # Publish (better than build for deployment)
            $publishDir = Join-Path $ApiPath "bin\Publish"
            if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
            
            & dotnet publish $buildTarget --configuration Release --output $publishDir 2>&1
            
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
            & npm install
            if ($LASTEXITCODE -ne 0) {
                Write-Error "npm install failed"
                return $null
            }
        }
        
        # Build for production
        Write-Host "Building Angular project for production..." -ForegroundColor Yellow
        & npm run build:prod
        if ($LASTEXITCODE -ne 0) {
            # Fallback to standard build if build:prod not found, or error? 
            # Let's try just build
            Write-Warning "'npm run build:prod' failed. Trying 'npm run build'..."
            & npm run build
        }

        if ($LASTEXITCODE -eq 0) {
            $wwwPath = Join-Path $UiPath "www"
            if (Test-Path $wwwPath) {
                Write-Host "Angular build successful" -ForegroundColor Green
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

# Main deployment function
function Start-Deployment {
    Write-Host "Loading configuration..." -ForegroundColor Gray
    $config = Load-Config
    
    if (-not $config) {
        Write-Error "Configuration could not be loaded. Please ensure 'deploy-config.json' exists and is valid."
        return
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
Start-Deployment
