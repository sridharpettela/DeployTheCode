#Requires -Version 5.1
# Test email script - sends a test message using the configured SMTP settings.

$EmailConfig = @{
    From     = "noreply@dinspire.in"
    To       = "mcsapideverror@dinspire.in"
    Host     = "dinspire.in"
    Port     = 25
    Username = "noreply@dinspire.in"
    Password = "60F4jlx%1"
    Subject  = "MicroCredit API Error (Dev)"
}

$testBody = @"
This is a test email from the DeployTheCode test-email script.

Sent at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Host: $($EmailConfig.Host)
Port: $($EmailConfig.Port)
"@

try {
    Write-Host "Sending test email..." -ForegroundColor Cyan
    Write-Host "  From: $($EmailConfig.From)" -ForegroundColor Gray
    Write-Host "  To:   $($EmailConfig.To)" -ForegroundColor Gray
    Write-Host "  Host: $($EmailConfig.Host):$($EmailConfig.Port)" -ForegroundColor Gray

    $smtp = New-Object System.Net.Mail.SmtpClient($EmailConfig.Host, $EmailConfig.Port)
    $smtp.EnableSSL = $false
    $smtp.Credentials = New-Object System.Net.NetworkCredential($EmailConfig.Username, $EmailConfig.Password)

    $message = New-Object System.Net.Mail.MailMessage
    $message.From = $EmailConfig.From
    $message.To.Add($EmailConfig.To)
    $message.Subject = "[TEST] $($EmailConfig.Subject)"
    $message.Body = $testBody
    $message.IsBodyHtml = $false

    $smtp.Send($message)
    $message.Dispose()

    Write-Host "Test email sent successfully to $($EmailConfig.To)." -ForegroundColor Green
}
catch {
    Write-Error "Failed to send test email: $_"
    exit 1
}
