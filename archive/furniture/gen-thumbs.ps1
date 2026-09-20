# Generates the 128x128 build-menu thumbnails for the security racks (System.Drawing, no external tools).
# The game requires exactly 128x128. Output: Furniture\Cybersecurity\Thumbs\<Name>.png
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Add-Type -AssemblyName System.Drawing
$outDir = Join-Path $Root "Furniture\Cybersecurity\Thumbs"
New-Item -ItemType Directory -Force $outDir | Out-Null

# file name, label, LED colour (must match ColorTertiaryDefault in the matching .tyd)
$racks = @(
    @{ File = "FirewallApplianceRack";  Label = "FW";  Led = "#FF4D2E" },
    @{ File = "SecurityMonitoringRack"; Label = "MON"; Led = "#2E8BFF" },
    @{ File = "BackupApplianceRack";    Label = "BAK"; Led = "#2ECC71" },
    @{ File = "KeyVaultRack";           Label = "KEY"; Led = "#FFC21A" }
)

function New-RoundedRect($x, $y, $w, $h, $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

foreach ($r in $racks) {
    $bmp = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)
    $led = [System.Drawing.ColorTranslator]::FromHtml($r.Led)

    # rack body
    $body = New-RoundedRect 30 6 68 116 6
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#2A2E35"))), $body)
    $g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml("#101216")), 3), $body)

    # accent stripe along the top
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $led), 36, 12, 56, 5)

    # five server units with an LED each
    for ($i = 0; $i -lt 5; $i++) {
        $y = 24 + $i * 15
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#3B424C"))), 36, $y, 56, 11)
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#20242A"))), 40, ($y + 3), 30, 5)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush $led), 79, ($y + 2), 7, 7)
    }

    # label
    $font = New-Object System.Drawing.Font("Arial", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($r.Label, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 30, 102, 68, 18), $fmt)

    $g.Dispose()
    $path = Join-Path $outDir ($r.File + ".png")
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $path"
}
