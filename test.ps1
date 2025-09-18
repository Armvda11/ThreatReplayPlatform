$projectDir = "c:\Users\Prince\OneDrive\Documents\ProjetPerso\ThreatReplayPlatform"
$outputFile = "$projectDir\all_files_content.txt"

# Créer/Écraser le fichier de sortie
"# Index of all files in ThreatReplayPlatform" | Out-File -FilePath $outputFile

# Parcourir tous les fichiers de façon récursive
Get-ChildItem -Path $projectDir -Recurse -File | ForEach-Object {
    $filePath = $_.FullName
    $relativePath = $filePath.Replace($projectDir, "").TrimStart("\")
    
    # Ajouter l'en-tête pour chaque fichier
    "`n`n" | Out-File -FilePath $outputFile -Append
    "=" * 80 | Out-File -FilePath $outputFile -Append
    "FILE: $relativePath" | Out-File -FilePath $outputFile -Append
    "=" * 80 | Out-File -FilePath $outputFile -Append
    
    # Ajouter le contenu du fichier
    # On évite d'inclure les fichiers binaires ou trop grands
    if ($_.Extension -match '^\.(txt|md|yml|yaml|json|js|ts|py|sh|ps1|cfg|conf|ini|xml|html|css|log|rules|config|properties)$' -and $_.Length -lt 1MB) {
        try {
            Get-Content $filePath -Raw | Out-File -FilePath $outputFile -Append
        }
        catch {
            "Unable to read file content: $_" | Out-File -FilePath $outputFile -Append
        }
    }
    else {
        "[Binary file or large file skipped]" | Out-File -FilePath $outputFile -Append
    }
}

Write-Host "Fichier de sortie créé: $outputFile"