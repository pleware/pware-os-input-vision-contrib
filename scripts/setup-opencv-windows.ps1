# The prebuilt OpenCV that mediapipe's Windows build links against.
#
# Windows does not compile OpenCV here, and that is upstream's own choice: setup.py
# says so in as many words ("On Windows, the opencv_cmake rule may need Visual
# Studio to compile OpenCV from source. For simplicity, we continue to link the
# prebuilt version of the OpenCV library through \"@windows_opencv//:opencv\"."),
# and third_party/opencv_windows.BUILD names the exact release and layout it wants:
#
#   OPENCV_VERSION = "3410"    x64/vc15/lib/opencv_world3410.lib
#
# WORKSPACE points that repository at C:\opencv\build, which is where upstream's own
# Windows instructions put it. Without it the analysis dies with
#
#   no such package '@@windows_opencv//': The repository's path is "C:\opencv\build"
#   (absolute: "C:/opencv/build") but this directory does not exist.
#
# i.e. a build that never starts, reported as a missing package.
#
# Downloads the official opencv-3.4.10-vc14_vc15 self-extracting archive (~183 MB)
# to %TEMP% and extracts it to C:\. Idempotent: the library path decides. ASCII
# only, on purpose: PowerShell 5.1 reads a BOM-less file as CP1252, and a non-ASCII
# byte (an em dash) makes it fail with "The string is missing the terminator".
$ErrorActionPreference = 'Stop'

$version = '3.4.10'
$world = 'C:\opencv\build\x64\vc15\lib\opencv_world3410.lib'
$log = Join-Path $env:LOCALAPPDATA 'pware-os\logs\setup-opencv.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

function Say([string]$message) {
    "$(Get-Date -Format 'HH:mm:ss') $message" | Add-Content -Path $log -Encoding UTF8
    Write-Host $message
}

if (Test-Path $world) {
    Say "OpenCV $version already at C:\opencv -- nothing to do"
    exit 0
}

$exe = Join-Path $env:TEMP "opencv-$version-vc14_vc15.exe"
$url = "https://github.com/opencv/opencv/releases/download/$version/opencv-$version-vc14_vc15.exe"

if (Test-Path $exe) {
    Say "using the archive already downloaded to $exe"
} else {
    Say "downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
}

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Say "extracting $size MB to C:\"
& $exe -o"C:\" -y | Out-Null

if (Test-Path $world) {
    Say "OpenCV $version ready at C:\opencv ($world)"
    exit 0
}

Say "FAILED: $world is still missing after extraction"
exit 1
