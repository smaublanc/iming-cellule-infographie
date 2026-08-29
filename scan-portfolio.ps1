# Scanne le dossier Portfolio (Images/{Categorie}/{Projet} + Films/{Projet})
# et regenere portfolio-inventory.json a partir de l'etat REEL du disque.
# A executer avant chaque generate-data-js.ps1 pour ne jamais travailler
# sur un inventaire perime.

$root = Join-Path $PSScriptRoot "Portfolio"
$imageExt = @(".jpg", ".jpeg", ".png")
$videoExt = @(".mp4", ".webm")
$vignetteNames = @("vignette.mp4", "vignette.webm")

# Fichiers video ignores faute de respecter la convention de nom (utile pour
# avertir l'utilisateur -- ex. un export brut d'outil IA pas encore renomme).
$script:ignoredVideos = @()

function Get-ProjectEntry($dir, $section, $category) {
  $folder = Split-Path $dir -Leaf
  if ($folder.StartsWith("0")) { return $null }  # convention : jamais public

  $files = Get-ChildItem -LiteralPath $dir -File
  $images = @($files | Where-Object { $imageExt -contains $_.Extension.ToLower() } | ForEach-Object { $_.Name } | Sort-Object)
  $videoFiles = @($files | Where-Object { $videoExt -contains $_.Extension.ToLower() })
  $hasTexte = [bool]($files | Where-Object { $_.Name -eq "texte.txt" })

  if ($section -eq "Films") {
    # Films : le vrai film livre, nom de fichier libre -- on prend le
    # premier trouve (meme convention que wp-import.php).
    $videoFile = $videoFiles | Select-Object -First 1
  } elseif ($videoFiles.Count -eq 1) {
    # Images, une seule video dans le dossier : pas d'ambiguite possible,
    # elle est prise comme vignette quel que soit son nom (export brut
    # d'un outil IA, etc. -- pas besoin de renommer).
    $videoFile = $videoFiles[0]
  } else {
    # Images, plusieurs videos dans le dossier : impossible de deviner
    # laquelle est la vignette voulue. On ne prend que celle nommee
    # EXACTEMENT "vignette.mp4"/".webm" (meme convention que main.js /
    # wp-import.php) et on signale les autres.
    $videoFile = $videoFiles | Where-Object { $vignetteNames -contains $_.Name.ToLower() } | Select-Object -First 1
    $others = $videoFiles | Where-Object { $_ -ne $videoFile }
    foreach ($o in $others) {
      $script:ignoredVideos += "$folder/$($o.Name)"
    }
  }

  [PSCustomObject]@{
    Section  = $section
    Category = $category
    Folder   = $folder
    Images   = $images
    Video    = if ($videoFile) { $videoFile.Name } else { $null }
    HasTexte = $hasTexte
  }
}

$entries = @()

$imagesRoot = Join-Path $root "Images"
if (Test-Path $imagesRoot) {
  foreach ($catDir in Get-ChildItem -LiteralPath $imagesRoot -Directory | Sort-Object Name) {
    foreach ($projDir in Get-ChildItem -LiteralPath $catDir.FullName -Directory | Sort-Object Name) {
      $e = Get-ProjectEntry $projDir.FullName "Images" $catDir.Name
      if ($e) { $entries += $e }
    }
  }
}

$filmsRoot = Join-Path $root "Films"
if (Test-Path $filmsRoot) {
  foreach ($projDir in Get-ChildItem -LiteralPath $filmsRoot -Directory | Sort-Object Name) {
    $e = Get-ProjectEntry $projDir.FullName "Films" "Films"
    if ($e) { $entries += $e }
  }
}

$entries | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 (Join-Path $PSScriptRoot "portfolio-inventory.json")
"Scanne : $($entries.Count) projets ($(@($entries | Where-Object { $_.Video }).Count) avec vignette video)"

if ($script:ignoredVideos.Count -gt 0) {
  Write-Host ""
  Write-Host "ATTENTION -- plusieurs videos dans un meme dossier, impossible de deviner laquelle est la vignette :"
  foreach ($v in $script:ignoredVideos) { Write-Host "  - $v" }
  Write-Host "Renomme celle voulue en 'vignette.mp4' (ou 'vignette.webm') pour qu'elle soit prise en compte."
}
