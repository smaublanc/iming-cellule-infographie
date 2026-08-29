# Met a jour le site (maquette) apres un changement dans Portfolio :
# nouvelle vignette video, nouvelles images, nouveau projet, renommage...
#
# A lancer (double-clic sur Mettre-a-jour-le-site.bat, a la racine) a
# chaque fois qu'un dossier de Portfolio a change. Deux etapes :
#   1) rescanne le disque -> portfolio-inventory.json (etat reel)
#   2) regenere maquette/js/data.js a partir de cet inventaire
# Le serveur d'apercu (preview-local.ps1) n'a pas besoin d'etre relance :
# il lit data.js a chaque requete. Il suffit de rafraichir la page.

$ErrorActionPreference = "Stop"

Write-Host "1/2 Analyse du dossier Portfolio..."
& (Join-Path $PSScriptRoot "scan-portfolio.ps1")

Write-Host "2/2 Regeneration du site (data.js)..."
& (Join-Path $PSScriptRoot "generate-data-js.ps1")

Write-Host ""
Write-Host "Termine. Rafraichis la page dans le navigateur (F5, ou Ctrl+Maj+R si besoin) pour voir le resultat."
