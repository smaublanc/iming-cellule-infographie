# Genere des versions web-optimisees des photos du Portfolio, SANS jamais
# toucher aux fichiers originaux (ce sont les fichiers source/qualite
# livraison -- on ne touche qu'a des copies derivees).
#
# Pour chaque image source (Portfolio/...) on genere dans Portfolio-web/...
# (meme chemin relatif) deux versions redimensionnees et recompressees :
#   - <nom>.card.jpg  -- pour les vignettes de grille (~900px de large max)
#   - <nom>.jpg       -- pour la galerie / le hero de page projet (~1800px)
# Incremental : une derivee deja a jour (plus recente que la source) n'est
# pas regeneree -- essentiel car ce script tourne a chaque mise a jour du
# site, pas seulement une fois.
#
# Les videos (vignette.mp4/webm, films) ne sont PAS traitees ici -- pas
# d'encodeur video disponible sans dependance externe. Voir les presets
# Adobe Media Encoder donnes separement pour compresser les vignettes a
# l'export.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$srcRoot = Join-Path $PSScriptRoot "Portfolio"
$dstRoot = Join-Path $PSScriptRoot "Portfolio-web"

$sizes = @(
  @{ Suffix = ".card"; MaxEdge = 900;  Quality = 78 }
  @{ Suffix = "";       MaxEdge = 1800; Quality = 82 }
)

function Get-JpegEncoder {
  [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
}
$jpegEncoder = Get-JpegEncoder

function Convert-OneImage($srcPath, $dstPath, $maxEdge, $quality) {
  $img = [System.Drawing.Image]::FromFile($srcPath)
  try {
    $w = $img.Width
    $h = $img.Height
    $scale = [Math]::Min(1.0, $maxEdge / [Math]::Max($w, $h))
    $newW = [Math]::Max(1, [int]($w * $scale))
    $newH = [Math]::Max(1, [int]($h * $scale))

    $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
    try {
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($img, 0, 0, $newW, $newH)
      } finally { $g.Dispose() }

      $dstDir = Split-Path $dstPath -Parent
      if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

      $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
      $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$quality)
      $bmp.Save($dstPath, $jpegEncoder, $encParams)
    } finally { $bmp.Dispose() }
  } finally { $img.Dispose() }
}

$processed = 0
$skipped = 0
$srcBytes = 0
$dstBytes = 0
$errors = @()

$imageFiles = Get-ChildItem -LiteralPath $srcRoot -Recurse -File | Where-Object { $_.Extension -match "^\.(jpe?g|png)$" -and -not $_.Directory.Name.StartsWith("0") }

foreach ($f in $imageFiles) {
  $rel = $f.FullName.Substring($srcRoot.Length + 1)
  $relNoExt = $rel.Substring(0, $rel.Length - $f.Extension.Length)

  foreach ($size in $sizes) {
    $dstRel = "$relNoExt$($size.Suffix).jpg"
    $dstPath = Join-Path $dstRoot $dstRel

    $needsWork = $true
    if (Test-Path -LiteralPath $dstPath) {
      $dstInfo = Get-Item -LiteralPath $dstPath
      if ($dstInfo.LastWriteTimeUtc -ge $f.LastWriteTimeUtc) { $needsWork = $false }
    }

    if ($needsWork) {
      try {
        Convert-OneImage -srcPath $f.FullName -dstPath $dstPath -maxEdge $size.MaxEdge -quality $size.Quality
        $processed++
      } catch {
        $errors += "  - $rel ($($size.Suffix)) : $($_.Exception.Message)"
      }
    } else {
      $skipped++
    }
  }
  $srcBytes += $f.Length
}

# Poids total genere (pour le rapport)
if (Test-Path $dstRoot) {
  $dstBytes = (Get-ChildItem -LiteralPath $dstRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum
}

$srcMo = [Math]::Round($srcBytes / 1MB, 1)
$dstMo = [Math]::Round($dstBytes / 1MB, 1)

"Images web : $processed generee(s)/mise(s) a jour, $skipped deja a jour."
"Poids sources (originaux, inchanges) : $srcMo Mo -- poids Portfolio-web (2 tailles x $($imageFiles.Count) photos) : $dstMo Mo"

if ($errors.Count -gt 0) {
  Write-Host ""
  Write-Host "ATTENTION -- erreurs sur $($errors.Count) fichier(s) :"
  $errors | ForEach-Object { Write-Host $_ }
}
