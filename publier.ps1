# Met a jour le site (scan + regeneration de data.js) puis publie tout
# sur GitHub (commit + push) -- le site en ligne (GitHub Pages) se met a
# jour automatiquement en ~1 minute apres le push.
# A lancer (double-clic sur Publier.bat) une fois content du resultat en
# apercu local.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "1/3 Mise a jour du site (scan Portfolio + data.js)..."
& (Join-Path $PSScriptRoot "maj-portfolio.ps1")

Write-Host ""
Write-Host "2/3 Verification des changements..."
$status = git status --porcelain
if (-not $status) {
  Write-Host "Rien a publier -- le depot est deja a jour."
  exit 0
}
git status --short

Write-Host ""
Write-Host "3/3 Publication sur GitHub..."
git add -A -- ':!*.log' ':!portfolio-inventory.json'
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
git commit -m "Mise a jour du portfolio - $date"
git push

Write-Host ""
Write-Host "Publie. Le site en ligne se mettra a jour dans environ 1 minute :"
Write-Host "https://smaublanc.github.io/iming-cellule-infographie/"
