# ============================
# 1. CHARGEMENT DE LA CONFIGURATION
# ============================
$configFile = "config.json"
if (-not (Test-Path -Path $configFile)) {
    Write-Host "Le fichier config.json est introuvable. Veuillez le créer." -ForegroundColor Red
    exit 1
}

# Charger la configuration JSON
$config = Get-Content -Path $configFile | ConvertFrom-Json

$usbVolumeName = $config.usbVolumeName
$backupRoot = $config.backupRoot
$minFreeSpaceMB = $config.minFreeSpaceMB
$useTimestampedFolder = $config.useTimestampedFolder
$sendEmailOnError = $config.sendEmailOnError
$emailSettings = $config.emailSettings
$silentMode = $config.silentMode
$excludedFileTypes = $config.excludedFileTypes

# Créer le dossier de sauvegarde s'il n'existe pas
if (-not (Test-Path -Path $backupRoot)) {
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
}

# ============================
# 2. FONCTIONS UTILES
# ============================

function Write-Log {
    param ([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp [$Level] - $Message"
    $logEntry | Out-File -Append -NoClobber -FilePath "$backupRoot\backup_log.txt"
    if (-not $silentMode) { Write-Output $logEntry }
}

function Send-Notification {
    param ([string]$Title, [string]$Message)
    if (Get-Module -ListAvailable -Name BurntToast) {
        Import-Module BurntToast -ErrorAction SilentlyContinue
        New-BurntToastNotification -Text $Title, $Message
    }
}

function Send-ErrorEmail {
    param ([string]$ErrorMessage)
    if ($sendEmailOnError) {
        try {
            $securePassword = ConvertTo-SecureString $emailSettings.credential.password -AsPlainText -Force
            $cred = New-Object PSCredential ($emailSettings.credential.username, $securePassword)
            Send-MailMessage -SmtpServer $emailSettings.smtpServer -From $emailSettings.from -To $emailSettings.to -Subject $emailSettings.subject -Body $ErrorMessage -Credential $cred -Port $emailSettings.port -UseSsl
            Write-Log "Email d'erreur envoyé."
        } catch { Write-Log "Erreur d'envoi de l'email: $_" "ERROR" }
    }
}

function Check-FreeSpace {
    param ([string]$Path, [int]$MinFreeMB)
    $driveLetter = ([System.IO.Path]::GetPathRoot($Path)).TrimEnd("\\")
    try {
        $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
        return ($drive.Free -ge ($MinFreeMB * 1MB))
    } catch {
        Write-Log "Erreur lors de la vérification de l'espace disque: $_" "ERROR"
        return $false
    }
}

function Backup-USB {
    param ([string]$driveLetter)
    Write-Log "Début de la sauvegarde depuis le lecteur $driveLetter"
    
    if (-not (Check-FreeSpace -Path $backupRoot -MinFreeMB $minFreeSpaceMB)) {
        Write-Log "Espace disque insuffisant." "ERROR"
        Send-Notification -Title "Backup USB" -Message "Espace disque insuffisant"
        Send-ErrorEmail -ErrorMessage "Espace disque insuffisant"
        return
    }

    $destinationFolderBase = Join-Path $backupRoot $usbVolumeName
    if (-not (Test-Path -Path $destinationFolderBase)) {
        New-Item -ItemType Directory -Path $destinationFolderBase | Out-Null
    }
    
    $destinationFolder = if ($useTimestampedFolder) { Join-Path $destinationFolderBase (Get-Date -Format "yyyyMMdd_HHmmss") } else { $destinationFolderBase }
    New-Item -ItemType Directory -Path $destinationFolder | Out-Null
    
    $sourcePath = "$driveLetter\\"
    $robocopyOptions = "/E /Z /NP /R:2 /W:5 /XO"
    if ($excludedFileTypes.Count -gt 0) { $robocopyOptions += " /XF " + ($excludedFileTypes -join " ") }
    
    $robocopyLog = Join-Path $destinationFolder "robocopy_log.txt"
    Start-Process -Wait -NoNewWindow -FilePath "robocopy" -ArgumentList "$sourcePath", "$destinationFolder", $robocopyOptions, "/LOG:$robocopyLog"
    
    if ($LASTEXITCODE -ge 8) {
        Write-Log "Erreur Robocopy: $LASTEXITCODE" "ERROR"
        Send-Notification -Title "Backup USB - Erreur" -Message "Erreur Robocopy: $LASTEXITCODE"
        Send-ErrorEmail -ErrorMessage "Erreur Robocopy: $LASTEXITCODE"
    } else {
        Write-Log "Sauvegarde réussie dans $destinationFolder"
        Send-Notification -Title "Backup USB - Succès" -Message "Sauvegarde terminée"
    }
}

# ============================
# 3. SURVEILLANCE USB
# ============================
Write-Log "Surveillance des périphériques USB activée."

$stopEvent = $false

$action = {
    param($Event)
    $vol = $Event.SourceEventArgs.NewEvent.TargetInstance
    if ($vol.Label -eq $using:usbVolumeName -and $vol.DriveLetter) {
        Write-Log "Clé USB détectée: $($vol.Label) sur $($vol.DriveLetter)."
        Start-Sleep -Seconds 3
        if (Test-Path ($vol.DriveLetter + "\\")) { Backup-USB -driveLetter $vol.DriveLetter }
    }
}

$query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Volume'"
$subscription = Register-WmiEvent -Query $query -Action $action -ErrorAction Stop

Write-Log "Attente de l'insertion de la clé USB '$usbVolumeName'."
while (-not $stopEvent) { Start-Sleep -Seconds 5 }

Unregister-Event -SourceIdentifier $subscription.Name
Write-Log "Surveillance USB arrêtée."
