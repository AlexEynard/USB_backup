# ⚡ Backup automatique de clé USB

Ce script PowerShell permet de **sauvegarder automatiquement le contenu d'une clé USB spécifique** dès son insertion dans un ordinateur Windows. Il utilise **Robocopy** pour une synchronisation incrémentale et intègre plusieurs fonctionnalités avancées pour garantir la fiabilité des sauvegardes, tout en restant léger et simple à utiliser.

## 📖 Fonctionnalités
- **Surveillance automatique** : Détection de l'insertion de la clé USB via WMI, sans intervention manuelle.
- **Vérification du nom de la clé** : Seule une clé USB avec un nom précis déclenche la sauvegarde, évitant toute copie accidentelle.
- **Sauvegarde incrémentale** : Copie uniquement les fichiers modifiés pour éviter les redondances et accélérer le processus.
- **Espace disque vérifié** : Annulation de la sauvegarde si l'espace disque est insuffisant, empêchant une surcharge du disque local.
- **Dossier horodaté (optionnel)** : Possibilité de créer des sauvegardes avec horodatage pour conserver l'historique et revenir à des versions antérieures.
- **Journalisation avancée** : Suivi détaillé des opérations et erreurs dans un fichier log pour un diagnostic plus facile.
- **Notifications Windows** : Utilisation du module BurntToast pour afficher des notifications lors du début et de la fin des sauvegardes.
- **Alerte email (optionnel)** : Envoi d'un email en cas d'erreur critique pour garantir une prise en charge rapide (SMTP requis).
- **Mode silencieux** : Option pour exécuter le script en arrière-plan sans affichage de fenêtres.
- **Exclusion de fichiers spécifiques** : Personnalisation des types de fichiers à exclure pour optimiser l'espace de stockage.

## 📝 Installation
### Prérequis
- **Windows** avec PowerShell 5.1 ou plus.
- Module **BurntToast** pour les notifications (facultatif) :
  ```powershell
  Install-Module BurntToast -Scope CurrentUser
  ```
- Configuration SMTP requise pour l'envoi des alertes par email (facultatif).

### Téléchargement
1. Clonez ce dépôt ou téléchargez le script :
   ```sh
   git clone https://github.com/AlexEynard/USB_backup.git
   ```
2. Placez le fichier `usb_backup.ps1` dans un dossier de votre choix.

## 💡 Utilisation
1. **Modifier les paramètres** dans le script (`usb_backup.ps1`) :
   - `$usbVolumeName = "MA_CLE_USB"` (Nom de la clé USB)
   - `$backupRoot = "C:\Users\VotreNom\Documents\SauvegardesUSB"` (Chemin de sauvegarde)
   - `$useTimestampedFolder = $true` (Activer les dossiers horodatés)
   - `$sendEmailOnError = $false` (Activer ou non les alertes email)
   - `$silentMode = $false` (Exécuter en arrière-plan sans affichage)
   - `$excludedFileTypes = @("*.tmp", "*.log")` (Exclure certains types de fichiers)
2. **Lancer le script** en mode administrateur :
   ```powershell
   powershell -ExecutionPolicy Bypass -File usb_backup.ps1
   ```
3. **Laisser tourner en arrière-plan** : Le script surveille l'insertion de la clé USB et effectue automatiquement la sauvegarde.
4. **Arrêter le script** : Fermez la fenêtre PowerShell ou utilisez `Ctrl + C`.
5. **Consulter les logs** : Vérifiez le fichier `backup_log.txt` pour suivre l'historique des sauvegardes.

## 📂 Structure du Projet
```
usb-backup/
├── usb_backup.ps1  # Script principal PowerShell
├── backup_log.txt  # Journalisation des sauvegardes (généré automatiquement)
├── README.md       # Documentation
├── config.json     # Fichier de configuration (optionnel)
```

## 📘 Licence
Ce projet est sous licence MIT. Vous pouvez le modifier et l'utiliser librement.

