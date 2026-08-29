param([int]$Port = 8899)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$rootWithSep = $root.TrimEnd('\') + '\'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
  $listener.Start()
} catch {
  Write-Host "Le serveur tourne deja sur le port $Port (ou le port est pris). Rien a faire."
  exit 0
}
Write-Host "Serving $root on http://localhost:$Port/"

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".css"  = "text/css"
  ".js"   = "application/javascript"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".png"  = "image/png"
  ".gif"  = "image/gif"
  ".svg"  = "image/svg+xml"
  ".mp4"  = "video/mp4"
  ".webm" = "video/webm"
}

# Traite une requête HTTP. Exécuté dans un runspace séparé par requête (voir
# le pool plus bas) pour qu'une requête lente (grosse vidéo) ne bloque pas
# les autres requêtes en attente.
$handler = {
  param($context, $root, $rootWithSep, $mime)
  $req = $context.Request
  $res = $context.Response
  try {
    # HttpListener decode deja une fois l'URL brute avant de nous la donner
    # via .AbsolutePath : un decodage manuel supplementaire ici casserait les
    # noms de fichiers contenant un "%" litteral (double decodage).
    $path = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if ($path -eq "/") { $path = "/maquette/index.html" }
    $fullPath = Join-Path $root ($path.TrimStart("/"))
    $fullPath = [System.IO.Path]::GetFullPath($fullPath)

    # Comparaison avec séparateur de dossier explicite : évite qu'un dossier
    # voisin dont le nom commence par les mêmes caractères que $root (ex.
    # "Studio Iming - Backup") ne passe la vérification.
    $inRoot = $fullPath.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) `
      -or $fullPath.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $inRoot) {
      $res.StatusCode = 403
      $res.Close()
      return
    }

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
      $ct = $mime[$ext]
      if (-not $ct) { $ct = "application/octet-stream" }
      $res.ContentType = $ct
      # Evite qu'un navigateur affiche une vieille version en cache (image,
      # HTML, JS, data.js...) apres une mise a jour des fichiers locaux.
      $res.Headers.Set("Cache-Control", "no-store, no-cache, must-revalidate")
      $res.Headers.Set("Pragma", "no-cache")
      $res.Headers.Set("Accept-Ranges", "bytes")
      $info = Get-Item -LiteralPath $fullPath
      $fileLength = $info.Length

      $start = 0
      $end = $fileLength - 1
      $rangeHeader = $req.Headers["Range"]
      if ($rangeHeader -and $rangeHeader -match "bytes=(\d*)-(\d*)") {
        if ($matches[1] -ne "") { $start = [int64]$matches[1] }
        if ($matches[2] -ne "") { $end = [int64]$matches[2] }
        if ($end -ge $fileLength) { $end = $fileLength - 1 }
        $res.StatusCode = 206
        $res.Headers.Set("Content-Range", "bytes $start-$end/$fileLength")
      }

      $length = $end - $start + 1
      $res.ContentLength64 = $length

      if ($req.HttpMethod -ne "HEAD") {
        $fs = [System.IO.File]::OpenRead($fullPath)
        try {
          $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
          $buffer = New-Object byte[] 65536
          $remaining = $length
          while ($remaining -gt 0) {
            $toRead = [Math]::Min($buffer.Length, $remaining)
            $read = $fs.Read($buffer, 0, $toRead)
            if ($read -le 0) { break }
            $res.OutputStream.Write($buffer, 0, $read)
            $remaining -= $read
          }
        } finally {
          $fs.Close()
        }
      }
    } else {
      $res.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes("Not found: $path")
      $res.ContentLength64 = $msg.Length
      if ($req.HttpMethod -ne "HEAD") {
        $res.OutputStream.Write($msg, 0, $msg.Length)
      }
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    try { $res.Close() } catch {}
  }
}

# Pool de runspaces : chaque requête est traitée dans son propre runspace,
# sans attendre que la précédente soit terminée (jusqu'à 8 en parallèle).
$pool = [runspacefactory]::CreateRunspacePool(1, 8)
$pool.Open()
$jobs = New-Object System.Collections.Generic.List[object]

while ($listener.IsListening) {
  $context = $listener.GetContext()

  $ps = [powershell]::Create()
  $ps.RunspacePool = $pool
  [void]$ps.AddScript($handler).AddArgument($context).AddArgument($root).AddArgument($rootWithSep).AddArgument($mime)
  $handle = $ps.BeginInvoke()
  $jobs.Add(@{ PS = $ps; Handle = $handle })

  # Nettoyage des requêtes terminées pour ne pas accumuler les instances.
  for ($i = $jobs.Count - 1; $i -ge 0; $i--) {
    if ($jobs[$i].Handle.IsCompleted) {
      try { $jobs[$i].PS.EndInvoke($jobs[$i].Handle) } catch {}
      $jobs[$i].PS.Dispose()
      $jobs.RemoveAt($i)
    }
  }
}
