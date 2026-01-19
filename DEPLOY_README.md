# MCS Deployment Script

This PowerShell script automates the deployment of both WebAPI and Angular/Ionic projects to an FTP server.

## Features

- **GUI Settings Form**: Easy-to-use Windows Forms interface for configuration
- **WebAPI Build**: Automatically builds .NET WebAPI project in Release configuration
- **Angular/Ionic Build**: Builds Angular/Ionic project for production
- **FTP Deployment**: Uploads both API and UI files to FTP server
- **Configuration Persistence**: Saves settings for future deployments

## Prerequisites

1. **.NET SDK** or **Visual Studio** (for WebAPI builds)
2. **Node.js and npm** (for Angular/Ionic builds)
3. **PowerShell 5.1 or later**

## Usage

1. **Run the script**:
   ```powershell
   .\deploy.ps1 -Environment Dev
   # Or Test, Prod
   #.\deploy.ps1 -Environment Dev
   # or
   #.\deploy.ps1 -Environment Test
   # or
   #.\deploy.ps1 -Environment Prod
   ```

2. **Configure settings** in the GUI form:
   - **WebAPI Project Path**: Path to your .NET WebAPI project folder (containing .csproj or .sln)
   - **Angular/Ionic Project Path**: Path to your Angular/Ionic project folder
   - **FTP Server URL**: FTP server address (e.g., `ftp://example.com`)
   - **FTP Username**: FTP login username
   - **FTP Password**: FTP login password
   - **API FTP Path** (optional): Remote FTP path for API files (default: `/api`)
   - **UI FTP Path** (optional): Remote FTP path for UI files (default: `/www`)

3. **Click "Save & Deploy"** to start the deployment process

## What the Script Does

1. **Builds WebAPI**:
   - Finds .csproj or .sln file in the specified path
   - Builds in Release configuration using `dotnet build` or MSBuild
   - Locates the Release output folder (typically `bin\Release`)

2. **Builds Angular/Ionic**:
   - Runs `npm install` if needed
   - Runs `npm run build:prod` to build for production
   - Ensures `www` folder is created with production build

3. **Deploys to FTP**:
   - Creates necessary directories on FTP server
   - Uploads all files from Release folder (API) and www folder (UI)
   - Shows progress for each file upload

## Configuration File

Settings are saved to `deploy-config.json` in the same directory as the script. This file contains:
- All paths and FTP credentials (password is stored in plain text - use with caution)

## Notes

- The script uses passive FTP mode for better firewall compatibility
- FTP passwords are stored in plain text in the config file
- The script creates directories on the FTP server as needed
- Build errors will stop the deployment process

## Troubleshooting

- **"dotnet not found"**: Install .NET SDK or use MSBuild from Visual Studio
- **"npm install failed"**: Check Node.js installation and network connectivity
- **"FTP upload failed"**: Verify FTP credentials and server accessibility
- **"Release folder not found"**: Check build output location in project settings
