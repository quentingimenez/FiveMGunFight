<#
.SYNOPSIS
  Capture une image de la fenêtre du jeu FiveM, même en arrière-plan.

.DESCRIPTION
  Utilise PrintWindow (drapeau PW_RENDERFULLCONTENT) : CopyFromScreen ne
  capturerait que la fenêtre de premier plan. Une capture à la fois : des
  captures en rafale font clignoter le jeu en noir, donc le script refuse une
  nouvelle capture moins de 5 secondes après la précédente.

  Windows PowerShell 5.1 :
    powershell -File scripts\capturer-jeu.ps1 -Sortie capture.png
    powershell -File scripts\capturer-jeu.ps1 -Sortie capture.png -Pleine

  Codes de sortie : 0 capture écrite, 1 jeu absent, 2 capture trop rapprochée.
  Ne publie jamais une capture sans l'avoir regardée (docs/debug-test.md § 6).
#>
param(
  [Parameter(Mandatory = $true)][string]$Sortie,
  # Taille réelle ; par défaut l'image est réduite de moitié (plus légère à lire).
  [switch]$Pleine
)

$marque = Join-Path $env:TEMP 'gf-capturer-jeu.derniere'
if (Test-Path $marque) {
  $ecart = (Get-Date) - (Get-Item $marque).LastWriteTime
  if ($ecart.TotalSeconds -lt 5) {
    Write-Error ('Capture refusée : la précédente date de {0:N1} s (minimum 5 s, le jeu clignote sinon).' -f $ecart.TotalSeconds)
    exit 2
  }
}

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GfCapture {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$jeu = Get-Process -Name 'FiveM_*GTAProcess' -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $jeu) {
  Write-Error 'Jeu introuvable : aucun processus FiveM_*GTAProcess avec une fenêtre.'
  exit 1
}

$rect = New-Object GfCapture+RECT
[GfCapture]::GetWindowRect($jeu.MainWindowHandle, [ref]$rect) | Out-Null
$largeur = $rect.Right - $rect.Left
$hauteur = $rect.Bottom - $rect.Top
$image = New-Object System.Drawing.Bitmap $largeur, $hauteur
$dessin = [System.Drawing.Graphics]::FromImage($image)
$dc = $dessin.GetHdc()
$ok = [GfCapture]::PrintWindow($jeu.MainWindowHandle, $dc, 2)
$dessin.ReleaseHdc($dc)
$dessin.Dispose()

if (-not $Pleine) {
  $reduite = New-Object System.Drawing.Bitmap $image, ([int]($largeur / 2)), ([int]($hauteur / 2))
  $image.Dispose()
  $image = $reduite
}
$chemin = [System.IO.Path]::GetFullPath($Sortie)
$image.Save($chemin, [System.Drawing.Imaging.ImageFormat]::Png)
$image.Dispose()
Set-Content -Path $marque -Value '' -Encoding ascii

'{0} ({1}x{2}, PrintWindow={3}) a {4:HH:mm:ss}' -f $chemin, $largeur, $hauteur, $ok, (Get-Date)
