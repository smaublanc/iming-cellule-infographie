# Met a jour le site (maquette) apres un changement dans Portfolio :
# nouvelle vignette video, nouvelles images, nouveau projet, renommage...
#
# A lancer (double-clic sur Mettre-a-jour-le-site.bat, a la racine) a
# chaque fois qu'un dossier de Portfolio a change. Trois etapes :
#   1) rescanne le disque -> portfolio-inventory.json (etat reel)
#   2) genere les versions web-optimisees des nouvelles/modifiees photos
#      (Portfolio-web/, voir compress-images.ps1 -- incremental, ne
#      retraite jamais une photo deja a jour)
#   3) regenere maquette/js/data.js + sitemap.xml a partir de l'inventaire
# Le serveur d'apercu (preview-local.ps1) n'a pas besoin d'etre relance :
# il lit ces fichiers a chaque requete. Il suffit de rafraichir la page.

$ErrorActionPreference = "Stop"

Write-Host "1/3 Analyse du dossier Portfolio..."
& (Join-Path $PSScriptRoot "scan-portfolio.ps1")

Write-Host ""
Write-Host "2/3 Optimisation des photos (Portfolio-web)..."
& (Join-Path $PSScriptRoot "compress-images.ps1")

Write-Host ""
Write-Host "3/3 Regeneration du site (data.js + sitemap.xml)..."
& (Join-Path $PSScriptRoot "generate-data-js.ps1")

Write-Host ""
Write-Host "Termine. Rafraichis la page dans le navigateur (F5, ou Ctrl+Maj+R si besoin) pour voir le resultat."
