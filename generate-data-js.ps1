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
"Genere : $($inventory.Count) projets"
