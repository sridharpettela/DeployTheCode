#Requires -Version 5.1
# MCS Deployment Script
# This script builds and deploys both WebAPI and Angular/Ionic projects to FTP

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
        } catch {
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
    } catch {
        Write-Error "Error saving config file: $_"
        return $false
    }
}

# Show settings form
function Show-SettingsForm {
    $config = Load-Config
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MCS Deployment Settings"
    $form.Size = New-Object System.Drawing.Size(600, 400)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    
    # API Path
    $lblApiPath = New-Object System.Windows.Forms.Label
    $lblApiPath.Location = New-Object System.Drawing.Point(10, 20)
    $lblApiPath.Size = New-Object System.Drawing.Size(150, 20)
    $lblApiPath.Text = "WebAPI Project Path:"
    $form.Controls.Add($lblApiPath)
    
    $txtApiPath = New-Object System.Windows.Forms.TextBox
    $txtApiPath.Location = New-Object System.Drawing.Point(170, 18)
    $txtApiPath.Size = New-Object System.Drawing.Size(350, 20)
    if ($config) { $txtApiPath.Text = $config.ApiPath }
    $form.Controls.Add($txtApiPath)
    
    $btnApiBrowse = New-Object System.Windows.Forms.Button
    $btnApiBrowse.Location = New-Object System.Drawing.Point(530, 16)
    $btnApiBrowse.Size = New-Object System.Drawing.Size(50, 25)
    $btnApiBrowse.Text = "Browse"
    $btnApiBrowse.Add_Click({
        $folder = New-Object System.Windows.Forms.FolderBrowserDialog
        $folder.Description = "Select WebAPI Project Folder"
        if ($folder.ShowDialog() -eq "OK") {
            $txtApiPath.Text = $folder.SelectedPath
        }
    })
    $form.Controls.Add($btnApiBrowse)
    
    # UI Path
    $lblUiPath = New-Object System.Windows.Forms.Label
    $lblUiPath.Location = New-Object System.Drawing.Point(10, 60)
    $lblUiPath.Size = New-Object System.Drawing.Size(150, 20)
    $lblUiPath.Text = "Angular/Ionic Project Path:"
    $form.Controls.Add($lblUiPath)
    
    $txtUiPath = New-Object System.Windows.Forms.TextBox
    $txtUiPath.Location = New-Object System.Drawing.Point(170, 58)
    $txtUiPath.Size = New-Object System.Drawing.Size(350, 20)
    if ($config) { $txtUiPath.Text = $config.UiPath }
    $form.Controls.Add($txtUiPath)
    
    $btnUiBrowse = New-Object System.Windows.Forms.Button
    $btnUiBrowse.Location = New-Object System.Drawing.Point(530, 56)
    $btnUiBrowse.Size = New-Object System.Drawing.Size(50, 25)
    $btnUiBrowse.Text = "Browse"
    $btnUiBrowse.Add_Click({
        $folder = New-Object System.Windows.Forms.FolderBrowserDialog
        $folder.Description = "Select Angular/Ionic Project Folder"
        if ($folder.ShowDialog() -eq "OK") {
            $txtUiPath.Text = $folder.SelectedPath
        }
    })
    $form.Controls.Add($btnUiBrowse)
    
    # FTP Server
    $lblFtpServer = New-Object System.Windows.Forms.Label
    $lblFtpServer.Location = New-Object System.Drawing.Point(10, 100)
    $lblFtpServer.Size = New-Object System.Drawing.Size(150, 20)
    $lblFtpServer.Text = "FTP Server URL:"
    $form.Controls.Add($lblFtpServer)
    
    $txtFtpServer = New-Object System.Windows.Forms.TextBox
    $txtFtpServer.Location = New-Object System.Drawing.Point(170, 98)
    $txtFtpServer.Size = New-Object System.Drawing.Size(410, 20)
    if ($config) { $txtFtpServer.Text = $config.FtpServer }
    $form.Controls.Add($txtFtpServer)
    
    # FTP Username
    $lblFtpUser = New-Object System.Windows.Forms.Label
    $lblFtpUser.Location = New-Object System.Drawing.Point(10, 140)
    $lblFtpUser.Size = New-Object System.Drawing.Size(150, 20)
    $lblFtpUser.Text = "FTP Username:"
    $form.Controls.Add($lblFtpUser)
    
    $txtFtpUser = New-Object System.Windows.Forms.TextBox
    $txtFtpUser.Location = New-Object System.Drawing.Point(170, 138)
    $txtFtpUser.Size = New-Object System.Drawing.Size(410, 20)
    if ($config) { $txtFtpUser.Text = $config.FtpUser }
    $form.Controls.Add($txtFtpUser)
    
    # FTP Password
    $lblFtpPass = New-Object System.Windows.Forms.Label
    $lblFtpPass.Location = New-Object System.Drawing.Point(10, 180)
    $lblFtpPass.Size = New-Object System.Drawing.Size(150, 20)
    $lblFtpPass.Text = "FTP Password:"
    $form.Controls.Add($lblFtpPass)
    
    $txtFtpPass = New-Object System.Windows.Forms.TextBox
    $txtFtpPass.Location = New-Object System.Drawing.Point(170, 178)
    $txtFtpPass.Size = New-Object System.Drawing.Size(410, 20)
    $txtFtpPass.PasswordChar = '*'
    if ($config) { $txtFtpPass.Text = $config.FtpPassword }
    $form.Controls.Add($txtFtpPass)
    
    # API FTP Path
    $lblApiFtpPath = New-Object System.Windows.Forms.Label
    $lblApiFtpPath.Location = New-Object System.Drawing.Point(10, 220)
    $lblApiFtpPath.Size = New-Object System.Drawing.Size(150, 20)
    $lblApiFtpPath.Text = "API FTP Path (optional):"
    $form.Controls.Add($lblApiFtpPath)
    
    $txtApiFtpPath = New-Object System.Windows.Forms.TextBox
    $txtApiFtpPath.Location = New-Object System.Drawing.Point(170, 218)
    $txtApiFtpPath.Size = New-Object System.Drawing.Size(410, 20)
    if ($config) { $txtApiFtpPath.Text = $config.ApiFtpPath }
    $form.Controls.Add($txtApiFtpPath)
    
    # UI FTP Path
    $lblUiFtpPath = New-Object System.Windows.Forms.Label
    $lblUiFtpPath.Location = New-Object System.Drawing.Point(10, 260)
    $lblUiFtpPath.Size = New-Object System.Drawing.Size(150, 20)
    $lblUiFtpPath.Text = "UI FTP Path (optional):"
    $form.Controls.Add($lblUiFtpPath)
    
    $txtUiFtpPath = New-Object System.Windows.Forms.TextBox
    $txtUiFtpPath.Location = New-Object System.Drawing.Point(170, 258)
    $txtUiFtpPath.Size = New-Object System.Drawing.Size(410, 20)
    if ($config) { $txtUiFtpPath.Text = $config.UiFtpPath }
    $form.Controls.Add($txtUiFtpPath)
    
    # Buttons
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Location = New-Object System.Drawing.Point(400, 300)
    $btnSave.Size = New-Object System.Drawing.Size(90, 30)
    $btnSave.Text = "Save & Deploy"
    $btnSave.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnSave)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Location = New-Object System.Drawing.Point(500, 300)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    
    $form.AcceptButton = $btnSave
    $form.CancelButton = $btnCancel
    
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $config = @{
            ApiPath = $txtApiPath.Text
            UiPath = $txtUiPath.Text
            FtpServer = $txtFtpServer.Text
            FtpUser = $txtFtpUser.Text
            FtpPassword = $txtFtpPass.Text
            ApiFtpPath = $txtApiFtpPath.Text
            UiFtpPath = $txtUiFtpPath.Text
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
        return $false
    }
    
    # Find .csproj or .sln file
    $csproj = Get-ChildItem -Path $ApiPath -Filter "*.csproj" -Recurse | Select-Object -First 1
    $sln = Get-ChildItem -Path $ApiPath -Filter "*.sln" -Recurse | Select-Object -First 1
    
    if (-not $csproj -and -not $sln) {
        Write-Error "No .csproj or .sln file found in $ApiPath"
        return $false
    }
    
    $buildTarget = if ($sln) { $sln.FullName } else { $csproj.FullName }
    
    Write-Host "Building: $buildTarget" -ForegroundColor Yellow
    
    # Build with dotnet or msbuild
    $dotnetPath = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnetPath) {
        Push-Location $ApiPath
        try {
            $buildResult = & dotnet build $buildTarget --configuration Release 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ WebAPI build successful" -ForegroundColor Green
                
                # Find Release folder
                $releasePath = Get-ChildItem -Path $ApiPath -Directory -Recurse -Filter "Release" | 
                    Where-Object { $_.FullName -like "*\bin\Release\*" } | 
                    Select-Object -First 1
                
                if ($releasePath) {
                    Write-Host "Release folder found: $($releasePath.FullName)" -ForegroundColor Green
                    return $releasePath.FullName
                } else {
                    Write-Warning "Release folder not found. Build may have succeeded but output location is unknown."
                    return $null
                }
            } else {
                Write-Error "WebAPI build failed"
                $buildResult | Write-Host
                return $false
            }
        } finally {
            Pop-Location
        }
    } else {
        # Try MSBuild
        $msbuildPath = "${env:ProgramFiles}\Microsoft Visual Studio\2022\*\MSBuild\Current\Bin\MSBuild.exe"
        $msbuild = Get-ChildItem -Path $msbuildPath -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($msbuild) {
            Push-Location $ApiPath
            try {
                & $msbuild.FullName $buildTarget /p:Configuration=Release /p:Platform="Any CPU" /t:Build
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ WebAPI build successful" -ForegroundColor Green
                    $releasePath = Get-ChildItem -Path $ApiPath -Directory -Recurse -Filter "Release" | 
                        Where-Object { $_.FullName -like "*\bin\Release\*" } | 
                        Select-Object -First 1
                    return $releasePath.FullName
                } else {
                    Write-Error "WebAPI build failed"
                    return $false
                }
            } finally {
                Pop-Location
            }
        } else {
            Write-Error "Neither dotnet nor MSBuild found. Please install .NET SDK or Visual Studio."
            return $false
        }
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
        return $false
    }
    
    Push-Location $UiPath
    try {
        # Check if node_modules exists
        if (-not (Test-Path "node_modules")) {
            Write-Host "Installing npm dependencies..." -ForegroundColor Yellow
            & npm install
            if ($LASTEXITCODE -ne 0) {
                Write-Error "npm install failed"
                return $false
            }
        }
        
        # Build for production
        Write-Host "Building Angular project for production..." -ForegroundColor Yellow
        & npm run build:prod
        if ($LASTEXITCODE -eq 0) {
            $wwwPath = Join-Path $UiPath "www"
            if (Test-Path $wwwPath) {
                Write-Host "✓ Angular build successful" -ForegroundColor Green
                Write-Host "Build output: $wwwPath" -ForegroundColor Green
                return $wwwPath
            } else {
                Write-Error "www folder not found after build"
                return $false
            }
        } else {
            Write-Error "Angular build failed"
            return $false
        }
    } finally {
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
    } catch {
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
            $ftpDirUri = "$baseFtpUri/$relativePath"
            Create-FtpDirectory -FtpUri $ftpDirUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null
        }
        
        # Upload files
        foreach ($file in $files) {
            $currentFile++
            $relativePath = $file.FullName.Substring($LocalPath.Length).Replace('\', '/').TrimStart('/')
            $ftpFileUri = "$baseFtpUri/$relativePath"
            
            Write-Progress -Activity "Uploading to FTP" -Status "Uploading $relativePath" -PercentComplete (($currentFile / $totalFiles) * 100)
            
            try {
                # Ensure parent directory exists
                $parentDir = Split-Path $relativePath -Parent
                if ($parentDir) {
                    $parentFtpUri = "$baseFtpUri/$parentDir"
                    Create-FtpDirectory -FtpUri $parentFtpUri -FtpUser $FtpUser -FtpPassword $FtpPassword | Out-Null
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
            } catch {
                $uploadErrors++
                Write-Warning "  ✗ Failed to upload: $relativePath - $_"
            }
        }
        
        Write-Progress -Activity "Uploading to FTP" -Completed
        
        if ($uploadErrors -eq 0) {
            Write-Host "✓ FTP upload completed successfully ($totalFiles files)" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "FTP upload completed with $uploadErrors errors out of $totalFiles files"
            return $false
        }
    } catch {
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
    
    # Validate configuration
    if ([string]::IsNullOrWhiteSpace($config.ApiPath) -or 
        [string]::IsNullOrWhiteSpace($config.UiPath) -or 
        [string]::IsNullOrWhiteSpace($config.FtpServer) -or 
        [string]::IsNullOrWhiteSpace($config.FtpUser) -or 
        [string]::IsNullOrWhiteSpace($config.FtpPassword)) {
        Write-Error "Please fill in all required fields (API Path, UI Path, FTP Server, Username, Password)"
        return
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   MCS Deployment Started" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $errors = @()
    
    # Build and deploy WebAPI
    if (-not [string]::IsNullOrWhiteSpace($config.ApiPath)) {
        $releasePath = Build-WebAPI -ApiPath $config.ApiPath
        if ($releasePath) {
            $apiFtpPath = if ([string]::IsNullOrWhiteSpace($config.ApiFtpPath)) { "/api" } else { $config.ApiFtpPath }
            $uploadResult = Upload-ToFtp -LocalPath $releasePath -FtpServer $config.FtpServer -FtpUser $config.FtpUser -FtpPassword $config.FtpPassword -FtpPath $apiFtpPath
            if (-not $uploadResult) {
                $errors += "WebAPI deployment failed"
            }
        } else {
            $errors += "WebAPI build failed"
        }
    }
    
    # Build and deploy Angular/Ionic
    if (-not [string]::IsNullOrWhiteSpace($config.UiPath)) {
        $wwwPath = Build-Angular -UiPath $config.UiPath
        if ($wwwPath) {
            $uiFtpPath = if ([string]::IsNullOrWhiteSpace($config.UiFtpPath)) { "/www" } else { $config.UiFtpPath }
            $uploadResult = Upload-ToFtp -LocalPath $wwwPath -FtpServer $config.FtpServer -FtpUser $config.FtpUser -FtpPassword $config.FtpPassword -FtpPath $uiFtpPath
            if (-not $uploadResult) {
                $errors += "UI deployment failed"
            }
        } else {
            $errors += "Angular build failed"
        }
    }
    
    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    if ($errors.Count -eq 0) {
        Write-Host "   Deployment Completed Successfully!" -ForegroundColor Green
    } else {
        Write-Host "   Deployment Completed with Errors:" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "   - $err" -ForegroundColor Red
        }
    }
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Run deployment
Start-Deployment
