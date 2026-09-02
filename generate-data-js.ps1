$inventory = Get-Content (Join-Path $PSScriptRoot "portfolio-inventory.json") -Raw | ConvertFrom-Json

function Slugify($text) {
  $normalized = $text.Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $normalized.ToCharArray()) {
    $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$sb.Append($ch)
    }
  }
  $s = $sb.ToString().ToLower()
  $s = $s -replace "[^a-z0-9]+", "-"
  $s = $s.Trim('-')
  return $s
}

function JsEscape($text) {
  return $text.Replace('\', '\\').Replace('"', '\"')
}

$catKeyMap = @{
  'Architecture' = 'architecture'
  'Autoroute' = 'autoroute'
  'Design' = 'design'
  'Industrie' = 'industrie'
  'IRVE' = 'irve'
  'Films' = 'films'
}

$projectBlocks = @()
$slugs = @()

foreach ($entry in $inventory) {
  $folder = $entry.Folder
  $parts = $folder -split '_', 2
  $client = $parts[0]
  $rest = if ($parts.Count -gt 1) { $parts[1] } else { '' }
  $emdash = [char]0x2014
  $title = if ($rest) { "$client $emdash $rest" } else { $client }
  $slug = Slugify $title
  $catKey = $catKeyMap[$entry.Category]

  if ($entry.Section -eq 'Films') {
    $basePath = "Portfolio/Films/$folder"
  } else {
    $basePath = "Portfolio/Images/$($entry.Category)/$folder"
  }

  $imagesJs = ($entry.Images | ForEach-Object { "      `"$basePath/$(JsEscape $_)`"," }) -join "`n"

  $videoLine = ""
  if ($entry.Video -and $entry.Video -isnot [System.Management.Automation.PSCustomObject] -and $entry.Video -ne "") {
    $videoLine = "    video: `"$basePath/$(JsEscape $entry.Video)`",`n"
  }

  $texteLine = ""
  if ($entry.HasTexte) {
    $texteLine = "    textFile: `"$basePath/texte.txt`",`n"
  }

  $block = @"
  {
    slug: "$slug",
    title: "$(JsEscape $title)",
    client: "$(JsEscape $client)",
    category: "$catKey",
$texteLine$videoLine    images: [
$imagesJs
    ],
  },
"@
  $projectBlocks += $block
  $slugs += $slug
}

$categoriesBlock = @"
const CATEGORIES = [
  { key: "architecture", label: "Architecture" },
  { key: "autoroute", label: "Autoroute" },
  { key: "design", label: "Design" },
  { key: "industrie", label: "Industrie" },
  { key: "irve", label: "IRVE" },
  { key: "films", label: "Films" },
];
"@

$header = @"
// Donnees du portfolio -- generees a partir du contenu reel de /Portfolio.
// Regenere automatiquement (generate-data-js.ps1) a chaque reorganisation
// du dossier Portfolio.
// Phase 3 (automatisation) remplacera ce fichier par un flux dynamique
// alimente par l'API WordPress (dossier depose -> page creee).

$categoriesBlock

const PROJECTS = [
$($projectBlocks -join "`n")
];
"@

$header | Out-File -Encoding utf8 (Join-Path $PSScriptRoot "maquette\js\data.js")

# ---------------------------------------------------------------------
# sitemap.xml -- regenere a chaque fois (liste des projets = liste des
# URLs), pour que les nouveaux projets soient decouvrables sans etape
# manuelle supplementaire.
$baseUrl = "https://smaublanc.github.io/iming-cellule-infographie"
$today = Get-Date -Format "yyyy-MM-dd"
$urlBlocks = @()
$urlBlocks += "  <url><loc>$baseUrl/maquette/index.html</loc><lastmod>$today</lastmod><changefreq>weekly</changefreq><priority>1.0</priority></url>"
$urlBlocks += "  <url><loc>$baseUrl/maquette/equipe.html</loc><lastmod>$today</lastmod><changefreq>monthly</changefreq><priority>0.5</priority></url>"
foreach ($slug in $slugs) {
  $urlBlocks += "  <url><loc>$baseUrl/maquette/projet.html?slug=$slug</loc><lastmod>$today</lastmod><changefreq>monthly</changefreq><priority>0.8</priority></url>"
}
$sitemap = @"
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$($urlBlocks -join "`n")
</urlset>
"@
# Out-File -Encoding utf8 ajoute un BOM en tete de fichier -- invalide pour
# un sitemap XML strict ("XML declaration allowed only at the start of the
# document" cote validateurs). On ecrit donc en UTF-8 sans BOM directement.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "sitemap.xml"), $sitemap, $utf8NoBom)

"Genere : $($inventory.Count) projets ($($slugs.Count) URLs dans sitemap.xml)"
