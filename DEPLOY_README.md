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
2. **Entity Framework Core tools** (for migrations): `dotnet tool install --global dotnet-ef` if you use migrations
3. **Node.js and npm** (for Angular/Ionic builds)
4. **PowerShell 5.1 or later**

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

1. **Runs database migrations first** (when `ConnectionString` is set in `deploy-config.json`):
   - Clones the API repository
   - Runs `dotnet ef database update --connection "<ConnectionString>"` against the target database
   - If migration fails, the deployment stops and Web API/UI are not deployed
   - If `ConnectionString` is empty, this step is skipped

2. **Builds and deploys Web API**:
   - Finds .csproj or .sln file in the cloned API path
   - Builds in Release configuration and publishes
   - Clears the API FTP path and uploads the published output

3. **Builds and deploys Angular/Ionic**:
   - Runs `npm install` if needed
   - Runs `npm run build:prod` to build for production
   - Ensures `www` folder is created with production build

4. **Deploys to FTP**:
   - Creates necessary directories on FTP server
   - Uploads all files from published API folder and www folder (UI)
   - Shows progress for each file upload

## Configuration File

Settings are in `deploy-config.json` in the same directory as the script. For each environment (Dev, Test, Prod):

- **Api.RepoUrl**, **Api.Branch**: Git repository for the Web API
- **Api.ConnectionString**: Database connection string used to run EF Core migrations **before** deploying. If set, migrations run first; if empty, migrations are skipped.
- **Api.SkipMigrations** (optional): Set to `true` to skip running migrations and deploy API/UI only. Use when you have "pending model changes" or run migrations separately.
- **Api.FtpServer**, **Api.FtpUser**, **Api.FtpPassword**, **Api.FtpPath**: FTP settings for the API
- **Ui.***: Same structure for the UI repo and FTP

Passwords and connection strings are stored in plain text; protect the file accordingly.

## Notes

- The script uses passive FTP mode for better firewall compatibility
- FTP passwords are stored in plain text in the config file
- The script creates directories on the FTP server as needed
- Build errors will stop the deployment process

## Troubleshooting

- **"dotnet not found"**: Install .NET SDK or use MSBuild from Visual Studio
- **"Database migration failed"**: (1) **EF tools version**: If you see "tools version '8.0.0' is older than runtime '9.0.13'", run `dotnet tool update --global dotnet-ef`. (2) **Pending model changes**: If the error says "pending changes" / "Add a new migration before updating", add a migration in the API repo (`dotnet ef migrations add <Name>`) and commit, then redeploy. To deploy without running migrations, set `Api.SkipMigrations: true` for that environment in deploy-config.json.
- **"npm install failed"**: Check Node.js installation and network connectivity
- **"FTP upload failed"**: Verify FTP credentials and server accessibility
- **"Release folder not found"**: Check build output location in project settings
