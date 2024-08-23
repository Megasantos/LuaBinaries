$logo = @"
  __  __                                  _
 |  \/  |                                | |
 | \  / | ___  __ _  __ _ ___  __ _ _ __ | |_ ___  ___
 | |\/| |/ _ \/ _` |/ _` / __|/ _` | '_ \| __/ _ \/ __|
 | |  | |  __/ (_| | (_| \__ \ (_| | | | | || (_) \__ \
 |_|  |_|\___|\__, |\__,_|___/\__,_|_| |_|\__\___/|___/
               __/ |
              |___/
"@

Write-Host $logo -ForegroundColor Cyan
Write-Host "Welcome to LuaBinaries!" -ForegroundColor Green

function CheckUrl($url) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head
        return $true
    } catch {
        return $false
    }
}

function CheckConnection($TargetName) {
    $maxTries = 3
    for ($i=1; $i -le $maxTries; $i++) {
        Write-Host "Checking connection: Attempt $i of $maxTries..."
        try {
            $connection = Test-Connection -ComputerName $TargetName -Count 1 -ErrorAction Stop
            Write-Host "Checking connection: PASSED" -ForegroundColor DarkGreen
            return
        }
        catch {
            if ($i -eq $maxTries) {
                Write-Host "Checking connection: FAILED" -ForegroundColor Red
                exit
            }
        }
    }
}

function CompileFile($vcvarsPath, $currentDirectory, $fileName, $commandString) {
    cmd /c "`"$vcvarsPath`" && $commandString"
    if ($?) {
        if (Test-Path $fileName) {
            Write-Host "Compilation successful, $fileName created."
        } else {
            Write-Host "Compilation failed, $fileName not found."
        }
    } else {
        Write-Host "Failed to execute the command."
    }
}

$currentDirectory = Get-Location

CheckConnection "www.lua.org"

$validVersion = $false
while (-not $validVersion) {
    Write-Host "Please enter the Lua version: " -ForegroundColor Green -NoNewline;
    $version = Read-Host
    $url = "https://www.lua.org/ftp/lua-$version.tar.gz"
    
    if (CheckUrl $url) {
        $validVersion = $true
    } else {
        Write-Host "Lua version $version does not exist. Please try again." -ForegroundColor Red
    }
}

$fileName = Split-Path -Path $url -Leaf
$outfile = Join-Path -Path $currentDirectory -ChildPath $fileName

$download = Start-BitsTransfer -Source $url -Destination $outfile -DisplayName "File Download" -Asynchronous
$previousStatus = $null

while ($download.JobState -in @("Transferring", "Connecting")) {
    if ($previousStatus -ne $download.JobState) {
        Write-Host "Download Status: $($download.JobState)" -ForegroundColor DarkYellow
        $previousStatus = $download.JobState;
    }
}

Switch($download.JobState)
{
    "Transferred" {
        Complete-BitsTransfer -BitsJob $download
        Write-Host "Download completed." -ForegroundColor DarkGreen
    }
    "Error" {
        $download | Format-List
        Write-Host "An error occurred during the download." -ForegroundColor Red
    }
    default {
        Write-Host "Status: $($download.JobState)" -ForegroundColor DarkYellow
    }
}

$tempDirectory = Join-Path -Path $currentDirectory -ChildPath "temp"
Remove-Item -Path $tempDirectory -Recurse -ErrorAction Ignore
New-Item -ItemType directory -Path $tempDirectory

tar -xvzf $outfile -C $tempDirectory
Remove-Item -Path $outfile

$srcDirectory = Get-ChildItem -Path $tempDirectory -Recurse | Where-Object { $_.PSIsContainer -and $_.Name -eq 'src' }
if ($srcDirectory) {
    $existingSrcDirectory = Join-Path -Path $currentDirectory -ChildPath 'src'
    if (Test-Path -Path $existingSrcDirectory) {
        Remove-Item -Path $existingSrcDirectory -Recurse
    }
    Move-Item -Path $srcDirectory.FullName -Destination $currentDirectory
}

Remove-Item -Path $tempDirectory -Recurse

$folders = @('bin', 'include')

foreach ($folder in $folders) {
    $fullPath = Join-Path -Path $currentDirectory -ChildPath $folder
    if (!(Test-Path -Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath | Out-Null
    }
}

$srcDirectoryPath = Join-Path -Path $currentDirectory -ChildPath 'src'
$includeDirectoryPath = Join-Path -Path $currentDirectory -ChildPath 'include'

$files = @('lauxlib.h', 'lua.h', 'lua.hpp', 'luaconf.h', 'lualib.h')

if (Test-Path -Path $includeDirectoryPath) {
    Remove-Item -Path $includeDirectoryPath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $includeDirectoryPath

foreach ($file in $files) {
    $filePath = Join-Path -Path $srcDirectoryPath -ChildPath $file
    if (Test-Path -Path $filePath) {
        Copy-Item -Path $filePath -Destination $includeDirectoryPath
    }
}

Set-Location -Path $srcDirectoryPath

$years = @(2017, 2019, 2022)
$editions = @("Professional", "Enterprise", "Community")

$possiblePaths = @()
foreach ($year in $years) {
    foreach ($edition in $editions) {
        $possiblePaths += "C:\Program Files\Microsoft Visual Studio\$year\$edition\VC\Auxiliary\Build\vcvarsamd64_x86.bat"
    }
}

# Find the first path that exists
$vcvarsPath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $vcvarsPath = $path
        break
    }
}

if ($vcvarsPath) {
    $resourceScript = "$currentDirectory\resource.rc"
    $resourceFile = "$currentDirectory\resource.res"
    & cmd /c "`"$vcvarsPath`" && rc.exe /fo $resourceFile $resourceScript"

    # Compile and link with the resource file
    CompileFile $vcvarsPath $currentdirectory lua.lib "cl /c /nologo /W3 /O1 /Ob1 /Oi /Gs /MTd *.c && del lua.obj luac.obj && link /LIB /out:lua.lib *.obj >NUL 2>&1"
    CompileFile $vcvarsPath $currentdirectory lua.dll "cl /c /nologo /W3 /O1 /Ob1 /Oi /Gs /MTd /DLUA_BUILD_AS_DLL /D_CRT_SECURE_NO_DEPRECATE *.c && del lua.obj luac.obj && link /DLL /out:lua.dll *.obj >NUL 2>&1"
    CompileFile $vcvarsPath $currentdirectory lua.exe "cl /c /nologo /W3 /O1 /Ob1 /Oi /Gs /MTd *.c && del luac.obj && link /out:lua.exe *.obj $resourceFile >NUL 2>&1"
    CompileFile $vcvarsPath $currentdirectory luac.exe "cl /c /nologo /W3 /O1 /Ob1 /Oi /Gs /MTd *.c && del lua.obj && link /out:luac.exe *.obj $resourceFile >NUL 2>&1"
} else {
    Write-Host "Could not find a valid Visual Studio environment setup script."
}

$filesToCopy = @(".\lua.lib", ".\lua.dll", ".\lua.exe", ".\luac.exe")
Copy-Item -Path $filesToCopy -Destination "$currentDirectory\bin" -ErrorAction SilentlyContinue

$filesToRemove = @(".\*.obj", ".\*.lib", ".\*.dll", ".\*.exp", ".\*.exe")
Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue

Remove-Item -Path $resourceFile -ErrorAction SilentlyContinue

Write-Host "Build completed"