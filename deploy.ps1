#Requires -Version 5.1
# MCS Deployment Script
# This script builds and deploys both WebAPI and Angular/Ionic projects to FTP
# Now supports cloning from Git, cleaning up local files, and separate FTP credentials.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

# Save configuration
function Save-Config {
    param($config)
    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
        return $true
    }
    catch {
        Write-Error "Error saving config file: $_"
        return $false
    }
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
            Write-Host "✓ Clone successful" -ForegroundColor Green
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
            Write-Host "✓ Cleaned up: $TargetDir" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Could not fully remove directory: $TargetDir. $_"
            return $false
        }
    }
    return $true
}

# Show settings form
function Show-SettingsForm {
    $config = Load-Config
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MCS Deployment Settings"
    $form.Size = New-Object System.Drawing.Size(700, 750)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.AutoScroll = $true

    $yPos = 20

    # --- API Section ---
    $grpApi = New-Object System.Windows.Forms.GroupBox
    $grpApi.Location = New-Object System.Drawing.Point(10, $yPos)
    $grpApi.Size = New-Object System.Drawing.Size(660, 240)
    $grpApi.Text = "WebAPI Configuration"
    $form.Controls.Add($grpApi)

    # API Repo
    $lblApiRepo = New-Object System.Windows.Forms.Label
    $lblApiRepo.Location = New-Object System.Drawing.Point(10, 25)
    $lblApiRepo.Size = New-Object System.Drawing.Size(100, 20)
    $lblApiRepo.Text = "Git Repo URL:"
    $grpApi.Controls.Add($lblApiRepo)

    $txtApiRepo = New-Object System.Windows.Forms.TextBox
    $txtApiRepo.Location = New-Object System.Drawing.Point(120, 22)
    $txtApiRepo.Size = New-Object System.Drawing.Size(520, 20)
    if ($config) { $txtApiRepo.Text = $config.ApiRepoUrl }
    $grpApi.Controls.Add($txtApiRepo)

    # API Branch
    $lblApiBranch = New-Object System.Windows.Forms.Label
    $lblApiBranch.Location = New-Object System.Drawing.Point(10, 55)
    $lblApiBranch.Size = New-Object System.Drawing.Size(100, 20)
    $lblApiBranch.Text = "Branch Name:"
    $grpApi.Controls.Add($lblApiBranch)

    $txtApiBranch = New-Object System.Windows.Forms.TextBox
    $txtApiBranch.Location = New-Object System.Drawing.Point(120, 52)
    $txtApiBranch.Size = New-Object System.Drawing.Size(200, 20)
    $txtApiBranch.Text = if ($config.ApiBranch) { $config.ApiBranch } else { "main" }
    $grpApi.Controls.Add($txtApiBranch)

    # API FTP Server
    $lblApiFtpSer = New-Object System.Windows.Forms.Label
    $lblApiFtpSer.Location = New-Object System.Drawing.Point(10, 85)
    $lblApiFtpSer.Size = New-Object System.Drawing.Size(100, 20)
    $lblApiFtpSer.Text = "FTP Server:"
    $grpApi.Controls.Add($lblApiFtpSer)

    $txtApiFtpSer = New-Object System.Windows.Forms.TextBox
    $txtApiFtpSer.Location = New-Object System.Drawing.Point(120, 82)
    $txtApiFtpSer.Size = New-Object System.Drawing.Size(520, 20)
    if ($config.ApiFtpServer) { $txtApiFtpSer.Text = $config.ApiFtpServer }
    $grpApi.Controls.Add($txtApiFtpSer)

    # API FTP User
    $lblApiFtpUse = New-Object System.Windows.Forms.Label
    $lblApiFtpUse.Location = New-Object System.Drawing.Point(10, 115)
    $lblApiFtpUse.Size = New-Object System.Drawing.Size(100, 20)
    $lblApiFtpUse.Text = "FTP User:"
    $grpApi.Controls.Add($lblApiFtpUse)

    $txtApiFtpUse = New-Object System.Windows.Forms.TextBox
    $txtApiFtpUse.Location = New-Object System.Drawing.Point(120, 112)
    $txtApiFtpUse.Size = New-Object System.Drawing.Size(200, 20)
    if ($config.ApiFtpUser) { $txtApiFtpUse.Text = $config.ApiFtpUser }
    $grpApi.Controls.Add($txtApiFtpUse)

    # API FTP Pass
    $lblApiFtpPass = New-Object System.Windows.Forms.Label
    $lblApiFtpPass.Location = New-Object System.Drawing.Point(330, 115)
    $lblApiFtpPass.Size = New-Object System.Drawing.Size(80, 20)
    $lblApiFtpPass.Text = "Password:"
    $grpApi.Controls.Add($lblApiFtpPass)

    $txtApiFtpPass = New-Object System.Windows.Forms.TextBox
    $txtApiFtpPass.Location = New-Object System.Drawing.Point(400, 112)
    $txtApiFtpPass.Size = New-Object System.Drawing.Size(240, 20)
    $txtApiFtpPass.PasswordChar = '*'
    if ($config.ApiFtpPassword) { $txtApiFtpPass.Text = $config.ApiFtpPassword }
    $grpApi.Controls.Add($txtApiFtpPass)

    # API FTP Path
    $lblApiFtpPath = New-Object System.Windows.Forms.Label
    $lblApiFtpPath.Location = New-Object System.Drawing.Point(10, 145)
    $lblApiFtpPath.Size = New-Object System.Drawing.Size(100, 20)
    $lblApiFtpPath.Text = "FTP Path:"
    $grpApi.Controls.Add($lblApiFtpPath)

    $txtApiFtpPath = New-Object System.Windows.Forms.TextBox
    $txtApiFtpPath.Location = New-Object System.Drawing.Point(120, 142)
    $txtApiFtpPath.Size = New-Object System.Drawing.Size(520, 20)
    $txtApiFtpPath.PlaceholderText = "(Optional) e.g. /"
    if ($config) { $txtApiFtpPath.Text = $config.ApiFtpPath }
    $grpApi.Controls.Add($txtApiFtpPath)


    $yPos += 250

    # --- UI Section ---
    $grpUi = New-Object System.Windows.Forms.GroupBox
    $grpUi.Location = New-Object System.Drawing.Point(10, $yPos)
    $grpUi.Size = New-Object System.Drawing.Size(660, 240)
    $grpUi.Text = "Angular/Ionic Configuration"
    $form.Controls.Add($grpUi)

    # UI Repo
    $lblUiRepo = New-Object System.Windows.Forms.Label
    $lblUiRepo.Location = New-Object System.Drawing.Point(10, 25)
    $lblUiRepo.Size = New-Object System.Drawing.Size(100, 20)
    $lblUiRepo.Text = "Git Repo URL:"
    $grpUi.Controls.Add($lblUiRepo)

    $txtUiRepo = New-Object System.Windows.Forms.TextBox
    $txtUiRepo.Location = New-Object System.Drawing.Point(120, 22)
    $txtUiRepo.Size = New-Object System.Drawing.Size(520, 20)
    if ($config) { $txtUiRepo.Text = $config.UiRepoUrl }
    $grpUi.Controls.Add($txtUiRepo)

    # UI Branch
    $lblUiBranch = New-Object System.Windows.Forms.Label
    $lblUiBranch.Location = New-Object System.Drawing.Point(10, 55)
    $lblUiBranch.Size = New-Object System.Drawing.Size(100, 20)
    $lblUiBranch.Text = "Branch Name:"
    $grpUi.Controls.Add($lblUiBranch)

    $txtUiBranch = New-Object System.Windows.Forms.TextBox
    $txtUiBranch.Location = New-Object System.Drawing.Point(120, 52)
    $txtUiBranch.Size = New-Object System.Drawing.Size(200, 20)
    $txtUiBranch.Text = if ($config.UiBranch) { $config.UiBranch } else { "main" }
    $grpUi.Controls.Add($txtUiBranch)

    # UI FTP Server
    $lblUiFtpSer = New-Object System.Windows.Forms.Label
    $lblUiFtpSer.Location = New-Object System.Drawing.Point(10, 85)
    $lblUiFtpSer.Size = New-Object System.Drawing.Size(100, 20)
    $lblUiFtpSer.Text = "FTP Server:"
    $grpUi.Controls.Add($lblUiFtpSer)

    $txtUiFtpSer = New-Object System.Windows.Forms.TextBox
    $txtUiFtpSer.Location = New-Object System.Drawing.Point(120, 82)
    $txtUiFtpSer.Size = New-Object System.Drawing.Size(520, 20)
    if ($config.UiFtpServer) { $txtUiFtpSer.Text = $config.UiFtpServer }
    $grpUi.Controls.Add($txtUiFtpSer)

    # UI FTP User
    $lblUiFtpUse = New-Object System.Windows.Forms.Label
    $lblUiFtpUse.Location = New-Object System.Drawing.Point(10, 115)
    $lblUiFtpUse.Size = New-Object System.Drawing.Size(100, 20)
    $lblUiFtpUse.Text = "FTP User:"
    $grpUi.Controls.Add($lblUiFtpUse)

    $txtUiFtpUse = New-Object System.Windows.Forms.TextBox
    $txtUiFtpUse.Location = New-Object System.Drawing.Point(120, 112)
    $txtUiFtpUse.Size = New-Object System.Drawing.Size(200, 20)
    if ($config.UiFtpUser) { $txtUiFtpUse.Text = $config.UiFtpUser }
    $grpUi.Controls.Add($txtUiFtpUse)

    # UI FTP Pass
    $lblUiFtpPass = New-Object System.Windows.Forms.Label
    $lblUiFtpPass.Location = New-Object System.Drawing.Point(330, 115)
    $lblUiFtpPass.Size = New-Object System.Drawing.Size(80, 20)
    $lblUiFtpPass.Text = "Password:"
    $grpUi.Controls.Add($lblUiFtpPass)

    $txtUiFtpPass = New-Object System.Windows.Forms.TextBox
    $txtUiFtpPass.Location = New-Object System.Drawing.Point(400, 112)
    $txtUiFtpPass.Size = New-Object System.Drawing.Size(240, 20)
    $txtUiFtpPass.PasswordChar = '*'
    if ($config.UiFtpPassword) { $txtUiFtpPass.Text = $config.UiFtpPassword }
    $grpUi.Controls.Add($txtUiFtpPass)

    # UI FTP Path
    $lblUiFtpPath = New-Object System.Windows.Forms.Label
    $lblUiFtpPath.Location = New-Object System.Drawing.Point(10, 145)
    $lblUiFtpPath.Size = New-Object System.Drawing.Size(100, 20)
    $lblUiFtpPath.Text = "FTP Path:"
    $grpUi.Controls.Add($lblUiFtpPath)

    $txtUiFtpPath = New-Object System.Windows.Forms.TextBox
    $txtUiFtpPath.Location = New-Object System.Drawing.Point(120, 142)
    $txtUiFtpPath.Size = New-Object System.Drawing.Size(520, 20)
    $txtUiFtpPath.PlaceholderText = "(Optional) e.g. /"
    if ($config) { $txtUiFtpPath.Text = $config.UiFtpPath }
    $grpUi.Controls.Add($txtUiFtpPath)

    $yPos += 260

    # Buttons
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(430, $yPos)
    $btnSave.Size = New-Object System.Drawing.Size(110, 35)
    $btnSave.Text = "Deploy"
    $btnSave.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnSave)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(550, $yPos)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 35)
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    
    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel
    
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $config = @{
            ApiRepoUrl     = $txtApiRepo.Text
            ApiBranch      = $txtApiBranch.Text
            ApiFtpPath     = $txtApiFtpPath.Text
            ApiFtpServer   = $txtApiFtpSer.Text
            ApiFtpUser     = $txtApiFtpUse.Text
            ApiFtpPassword = $txtApiFtpPass.Text

            UiRepoUrl      = $txtUiRepo.Text
            UiBranch       = $txtUiBranch.Text
            UiFtpPath      = $txtUiFtpPath.Text
            UiFtpServer    = $txtUiFtpSer.Text
            UiFtpUser      = $txtUiFtpUse.Text
            UiFtpPassword  = $txtUiFtpPass.Text
        }
        Save-Config $config
        return $config
    }
    return $null
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
                Write-Host "✓ WebAPI publish successful" -ForegroundColor Green
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
                Write-Host "✓ Angular build successful" -ForegroundColor Green
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
                
                Write-Host "  ✓ Uploaded: $relativePath" -ForegroundColor Green
            }
            catch {
                $uploadErrors++
                Write-Warning "  ✗ Failed to upload: $relativePath - $_"
            }
        }
        
        Write-Progress -Activity "Uploading to FTP" -Completed
        
        if ($uploadErrors -eq 0) {
            Write-Host "✓ FTP upload completed successfully ($totalFiles files)" -ForegroundColor Green
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
    $config = Show-SettingsForm
    
    if (-not $config) {
        Write-Host "Deployment cancelled by user." -ForegroundColor Yellow
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
