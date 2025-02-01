<#
.SYNOPSIS
   Sauvegarde automatique de la clé USB spécifiée dès son insertion dans le PC.

.DESCRIPTION
   Ce script surveille en continu l'insertion d'un volume USB dont le label correspond à celui défini en configuration.
   Lorsqu'il est détecté, le script :
     - Vérifie l’espace disque disponible sur le disque de destination.
     - Crée un dossier de sauvegarde (avec horodatage optionnel).
     - Lance une synchronisation incrémentale via Robocopy en excluant certains fichiers si besoin.
     - Journalise toutes les opérations dans un fichier log.
     - Envoie des notifications Windows et/ou un email en cas de problème.
     - Possède un mode silencieux permettant de s'exécuter en arrière-plan sans afficher d'informations à l'écran.
#>

# ============================
# 1. CONFIGURATION
# ============================

# Nom du volume de la clé USB (tel qu'affiché dans l'explorateur Windows)
$usbVolumeName = "MA_CLE_USB"  # Remplacez par le label exact de votre clé USB

# Dossier de destination (exemple : dans "Mes documents")
$documentsPath = [Environment]::GetFolderPath("MyDocuments")
# Dossier racine pour les sauvegardes
$backupRoot = Join-Path $documentsPath "SauvegardesUSB"

# Créer le dossier racine de sauvegarde s'il n'existe pas
if (-not (Test-Path -Path $backupRoot)) {
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
}

# Espace minimum requis (en Mo) sur le disque de destination
$minFreeSpaceMB = 500

# Option : Créer un sous-dossier horodaté pour chaque sauvegarde
$useTimestampedFolder = $true

# Paramètres pour l’envoi d’email en cas d’erreur critique (optionnel)
$sendEmailOnError = $false
$emailSettings = @{
    SmtpServer   = "smtp.votresmtp.com"
    From         = "backup@votre-domaine.com"
    To           = "admin@votre-domaine.com"
    Subject      = "Erreur Backup USB"
    Credential   = (Get-Credential -Message "Entrer les identifiants SMTP")
    Port         = 587
}

# Nouveau paramètre : Mode silencieux (true = aucune sortie console, mais log et notifications demeurent)
$silentMode = $false

# Nouveau paramètre : Types de fichiers à exclure lors de la copie
$excludedFileTypes = @("*.tmp", "*.log")

# ============================
# 2. FONCTIONS UTILES
# ============================

# Fonction pour écrire dans le log et afficher dans la console (si non en mode silencieux)
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp [$Level] - $Message"
    $global:logContent += $logEntry + "`n"
    Add-Content -Path $global:logFile -Value $logEntry
    if (-not $silentMode) {
        Write-Output $logEntry
    }
}

# Fonction pour envoyer une notification Windows (si le module BurntToast est installé)
function Send-Notification {
    param (
        [string]$Title,
        [string]$Message
    )
    try {
        if (Get-Module -ListAvailable -Name BurntToast) {
            Import-Module BurntToast -ErrorAction Stop
            New-BurntToastNotification -Text $Title, $Message
        }
    }
    catch {
        Write-Log "Le module BurntToast n'est pas installé ou n'a pas pu être chargé." "WARNING"
    }
}

# Fonction pour envoyer un email en cas d'erreur (optionnel)
function Send-ErrorEmail {
    param (
        [string]$ErrorMessage
    )
    if ($sendEmailOnError) {
        try {
            Send-MailMessage -SmtpServer $emailSettings.SmtpServer `
                             -From $emailSettings.From `
                             -To $emailSettings.To `
                             -Subject $emailSettings.Subject `
                             -Body $ErrorMessage `
                             -Credential $emailSettings.Credential `
                             -Port $emailSettings.Port -UseSsl
            Write-Log "Email d'erreur envoyé."
        }
        catch {
            Write-Log "Erreur lors de l'envoi de l'email: $_" "ERROR"
        }
    }
}

# Fonction pour vérifier l'espace libre sur le disque de destination
function Check-FreeSpace {
    param (
        [string]$Path,
        [int]$MinFreeMB
    )
    try {
        $driveLetter = ([System.IO.Path]::GetPathRoot($Path)).TrimEnd("\")
        $drive = Get-PSDrive -Name $driveLetter
        if ($drive.Free -lt ($MinFreeMB * 1MB)) {
            return $false
        }
        return $true
    }
    catch {
        Write-Log "Erreur lors de la vérification de l'espace disque: $_" "ERROR"
        return $false
    }
}

# Fonction principale pour réaliser la sauvegarde
function Backup-USB {
    param (
        [string]$driveLetter  # Ex: "E:"
    )

    Write-Log "Début de la sauvegarde depuis le lecteur $driveLetter"

    # Vérifier si l'espace libre est suffisant
    if (-not (Check-FreeSpace -Path $backupRoot -MinFreeMB $minFreeSpaceMB)) {
        $msg = "Espace disque insuffisant sur la destination ($backupRoot). Sauvegarde annulée."
        Write-Log $msg "ERROR"
        Send-Notification -Title "Backup USB" -Message $msg
        Send-ErrorEmail -ErrorMessage $msg
        return
    }

    try {
        # Créer le dossier de sauvegarde spécifique à cette clé USB
        $destinationFolderBase = Join-Path $backupRoot $usbVolumeName
        if (-not (Test-Path -Path $destinationFolderBase)) {
            New-Item -ItemType Directory -Path $destinationFolderBase | Out-Null
        }

        # Création d'un dossier horodaté pour garder l'historique si activé
        if ($useTimestampedFolder) {
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $destinationFolder = Join-Path $destinationFolderBase $timestamp
            New-Item -ItemType Directory -Path $destinationFolder | Out-Null
        }
        else {
            $destinationFolder = $destinationFolderBase
        }

        # Définir le chemin source de la clé USB
        $sourcePath = $driveLetter + "\"
        
        # Construire la commande Robocopy avec options de base
        $robocopyOptions = "/E /Z /NP /R:2 /W:5 /XO"
        # Ajout des options pour exclure certains types de fichiers si la liste n'est pas vide
        if ($excludedFileTypes.Count -gt 0) {
            $excludeString = $excludedFileTypes -join " "
            $robocopyOptions += " /XF $excludeString"
        }
        $robocopyLog = Join-Path $destinationFolder "robocopy_log.txt"
        $cmd = "robocopy `"$sourcePath`" `"$destinationFolder`" $robocopyOptions /LOG:`"$robocopyLog`""
        Write-Log "Lancement de la commande Robocopy : $cmd"

        # Exécuter la commande Robocopy
        $robocopyResult = Invoke-Expression $cmd

        # Vérifier le code de sortie de Robocopy
        # Robocopy renvoie des codes (0 = rien copié, 1 = copie réussie, > 8 = erreurs critiques)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ge 8) {
            $msg = "Erreur lors de la sauvegarde via Robocopy. Code d'erreur : $exitCode"
            Write-Log $msg "ERROR"
            Send-Notification -Title "Backup USB - Erreur" -Message $msg
            Send-ErrorEmail -ErrorMessage $msg
        }
        else {
            $msg = "Sauvegarde terminée avec succès sur le dossier $destinationFolder (code Robocopy : $exitCode)"
            Write-Log $msg
            Send-Notification -Title "Backup USB - Succès" -Message $msg
        }
    }
    catch {
        $msg = "Exception lors de la sauvegarde: $_"
        Write-Log $msg "ERROR"
        Send-Notification -Title "Backup USB - Exception" -Message $msg
        Send-ErrorEmail -ErrorMessage $msg
    }
}

# ============================
# 3. INITIALISATION DU LOG
# ============================
$global:logFile = Join-Path $backupRoot "backup_log.txt"
$global:logContent = ""
if (-not (Test-Path -Path $global:logFile)) {
    New-Item -ItemType File -Path $global:logFile -Force | Out-Null
}
Write-Log "=== Démarrage du script de backup USB ==="

# ============================
# 4. SURVEILLANCE USB via WMI
# ============================
Write-Log "Mise en place de la surveillance des périphériques USB..."

# ScriptBlock déclenché à chaque création d'un volume
$action = {
    param($Event)
    $vol = $Event.SourceEventArgs.NewEvent.TargetInstance

    # Vérifier que le volume possède un label et une lettre de lecteur
    if ($vol.Label -and $vol.DriveLetter) {
        if (-not $silentMode) {
            Write-Output "Volume détecté: $($vol.Label) sur $($vol.DriveLetter)"
        }
        if ($vol.Label -eq $using:usbVolumeName) {
            Write-Log "Clé USB '$($vol.Label)' détectée sur le lecteur $($vol.DriveLetter)."
            # Petite pause pour s'assurer que la clé est correctement montée
            Start-Sleep -Seconds 3

            # Vérifier que la clé est toujours présente avant de lancer la sauvegarde
            if (Test-Path ($vol.DriveLetter + "\")) {
                Backup-USB -driveLetter $vol.DriveLetter
            }
            else {
                Write-Log "Le lecteur $($vol.DriveLetter) n'est plus accessible." "WARNING"
            }
        }
    }
}

# Requête WMI pour détecter l'insertion d'un volume
$query = "SELECT * FROM __InstanceCreationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_Volume'"
$subscription = Register-WmiEvent -Query $query -Action $action -ErrorAction Stop

Write-Log "Surveillance active. Le script attend l'insertion de la clé USB '$usbVolumeName'."
Write-Log "Appuyez sur Ctrl+C pour arrêter le script."

# Boucle infinie pour garder le script actif
try {
    while ($true) {
        Start-Sleep -Seconds 5
    }
}
catch [System.Exception] {
    Write-Log "Exception lors de l'exécution principale: $_" "ERROR"
}
finally {
    Write-Log "Arrêt du script. Désinscription des événements."
    Unregister-Event -SourceIdentifier $subscription.Name
}
