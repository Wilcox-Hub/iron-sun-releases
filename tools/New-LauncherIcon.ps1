param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$bitmap=[Drawing.Bitmap]::new(256,256)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([Drawing.Color]::FromArgb(17,24,23))
$pen=[Drawing.Pen]::new([Drawing.Color]::FromArgb(255,189,114),13)
try {
 $graphics.DrawEllipse($pen,44,44,168,168)
 $graphics.DrawLine($pen,76,128,180,128)
 $graphics.DrawLine($pen,128,76,128,180)
 $stream=[IO.MemoryStream]::new()
 try {
  $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
  $png=$stream.ToArray()
  $output=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($output)
  try {
   $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1)
   $writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0)
   $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$png.Length);$writer.Write([uint32]22);$writer.Write($png)
   [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot '../assets/iron-sun.ico'),$output.ToArray())
  } finally {$writer.Dispose();$output.Dispose()}
 } finally {$stream.Dispose()}
} finally {$pen.Dispose();$graphics.Dispose();$bitmap.Dispose()}
