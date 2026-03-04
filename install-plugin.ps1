## Configure this
$Host.UI.RawUI.WindowTitle = "Galapasteam plugin installer | galapasteam"
$name = "galapasteam" # automatic first letter uppercase included
$link = "https://github.com/jhon1466/galapasteam/releases/latest/download/galapasteam.zip"
$milleniumTimer = 5 # in seconds for auto-installation

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

#### SISTEMA DE SUSCRIPCIÓN (FIREBASE) ####
$ProjectID = "galapasteam-48065" # Project ID de Firebase Real
$DatabaseURL = "https://firestore.googleapis.com/v1/projects/$ProjectID/databases/(default)/documents/licenses"

function Check-Subscription {
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   GALAPASTEAM | VALIDACIÓN FIREBASE      " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    
    $key = Read-Host "Ingresa tu License Key"
    
    if ([string]::IsNullOrWhiteSpace($key)) {
        Write-Host "[!] La clave no puede estar vacía." -ForegroundColor Red
        exit
    }

    Write-Host "Conectando con el servidor..." -ForegroundColor Yellow
    try {
        # Consulta a Firestore REST API
        $response = Invoke-RestMethod -Uri $DatabaseURL
        
        # Buscamos el documento que tenga el ID igual a nuestra key
        $licenseDoc = $response.documents | Where-Object { 
            $_.fields.id.stringValue -eq $key
        }

        if ($null -eq $licenseDoc) {
            Write-Host "[ERR] Clave inválida o no encontrada en el sistema." -ForegroundColor Red
            exit
        }

        # --- TELEMETRÍA: ENVIAR DATOS DE LA PC ---
        try {
            $PCName = $env:COMPUTERNAME
            $WinUser = $env:USERNAME
            $UpdateBody = @{
                fields = @{
                    pcName = @{ stringValue = $PCName }
                    windowsUser = @{ stringValue = $WinUser }
                    lastActive = @{ timestampValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
                }
            } | ConvertTo-Json -Depth 10
            
            # Actualizamos los campos en Firestore
            $PatchURL = "$($DatabaseURL)/$($key)?updateMask.fieldPaths=pcName&updateMask.fieldPaths=windowsUser&updateMask.fieldPaths=lastActive"
            Invoke-RestMethod -Uri $PatchURL -Method Patch -Body $UpdateBody -ContentType "application/json" -ErrorAction SilentlyContinue
        } catch { }

        $expString = $licenseDoc.fields.expiresAt.timestampValue
        $expirationDate = [DateTime]::Parse($expString)
        $today = Get-Date

        if ($today -gt $expirationDate) {
            Write-Host "[ERR] Tu suscripción expiró el $expString." -ForegroundColor Red
            Write-Host "[!] Eliminando archivos por falta de pago..." -ForegroundColor Yellow
            
            $steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath
            $pluginPath = Join-Path $steamPath "plugins\$name"
            
            if (Test-Path $pluginPath) {
                Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
                Remove-Item -Path $pluginPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "[OK] Archivos eliminados." -ForegroundColor Green
            }
            exit
        }

        Write-Host "[OK] Licencia validada correctamente ($($licenseDoc.fields.plan.stringValue))." -ForegroundColor Green
        
        # Persistencia en Registro
        $registryPath = "HKCU:\Software\$upperName"
        if (-not (Test-Path $registryPath)) { New-Item $registryPath -Force | Out-Null }
        Set-ItemProperty -Path $registryPath -Name "LicenseKey" -Value $key
        Set-ItemProperty -Path $registryPath -Name "InstallURL" -Value $DatabaseURL

        # CREAR TAREA PROGRAMADA (Invisible)
        $taskName = "UpdateChecker_$upperName"
        $actionScript = {
            $regPath = "HKCU:\Software\Galapasteam"
            $storedKey = (Get-ItemProperty $regPath).LicenseKey
            $url = (Get-ItemProperty $regPath).InstallURL
            $name = "galapasteam"
            
            try {
                $response = Invoke-RestMethod -Uri $url
                $lic = $response.documents | Where-Object { $_.fields.id.stringValue -eq $storedKey }
                $exp = [DateTime]::Parse($lic.fields.expiresAt.timestampValue)
                
                if ((Get-Date) -gt $exp) {
                    $steam = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath
                    $plug = Join-Path $steam "plugins\$name"
                    if (Test-Path $plug) {
                        Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
                        Remove-Item $plug -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {}
        }.ToString()

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"$actionScript`""
        $trigger = New-ScheduledTaskTrigger -DailyAt 12:00PM
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Garantiza que $name esté al día con la suscripción." -Force | Out-Null
        
        Write-Host "[i] Expira el: $expString" -ForegroundColor Gray
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Host "[ERR] No se pudo conectar a Firebase. Revisa tu conexión." -ForegroundColor Red
        exit
    }
}

# Ejecutar validación
Check-Subscription
#########################################



# Hidden defines
$steam = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam").InstallPath
$upperName = $name.Substring(0, 1).ToUpper() + $name.Substring(1).ToLower()

#### Logging defines ####
function Log {
    param ([string]$Type, [string]$Message, [boolean]$NoNewline = $false)

    $Type = $Type.ToUpper()
    switch ($Type) {
        "OK" { $foreground = "Green" }
        "INFO" { $foreground = "Cyan" }
        "ERR" { $foreground = "Red" }
        "WARN" { $foreground = "Yellow" }
        "LOG" { $foreground = "Magenta" }
        "AUX" { $foreground = "DarkGray" }
        default { $foreground = "White" }
    }

    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor "Cyan" -NoNewline

    Write-Host [$Type] $Message -ForegroundColor $foreground -NoNewline:$NoNewline
}
Log "WARN" "Hey! Just letting you know that i'm working on a new version combining various scripts of the server"
Log "AUX" "Will include language support on THIS script too, luv y'all brazilians"
Write-Host

# To hide IEX blue box thing
$ProgressPreference = 'SilentlyContinue'



Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force


#### Requirements part ####

# Steamtools check
# TODO: Make this prettier?
$path = Join-Path $steam "xinput1_4.dll"
if ( Test-Path $path ) {
    Log "INFO" "Steamtools already installed"
}
else {
    # Filtering the installation script
    $script = Invoke-RestMethod "https://steam.run"
    $keptLines = @()

    foreach ($line in $script -split "`n") {
        $conditions = @( # Removes lines containing one of those
            ($line -imatch "Start-Process" -and $line -imatch "steam"),
            ($line -imatch "steam\.exe"),
            ($line -imatch "Start-Sleep" -or $line -imatch "Write-Host"),
            ($line -imatch "cls" -or $line -imatch "exit"),
            ($line -imatch "Stop-Process" -and -not ($line -imatch "Get-Process"))
        )
        
        if (-not($conditions -contains $true)) {
            $keptLines += $line
        }
    }

    $SteamtoolsScript = $keptLines -join "`n"
    Log "ERR" "Steamtools not found."
    
    # Retrying with a max of 5
    for ($i = 0; $i -lt 5; $i++) {

        Log "AUX" "Install it at your own risk! Close this script if you don't want to."
        Log "WARN" "Pressing any key will install steamtools (UI-less)."
        
        [void][System.Console]::ReadKey($true)
        Write-Host
        Log "WARN" "Installing Steamtools"
        
        Invoke-Expression $SteamtoolsScript *> $null

        if ( Test-Path $path ) {
            Log "OK" "Steamtools installed"
            break
        }
        else {
            Log "ERR" "Steamtools installation failed, retrying..."
        }

    }
}

# Millenium check
$milleniumInstalling = $false
foreach ($file in @("millennium.dll", "python311.dll")) {
    if (!( Test-Path (Join-Path $steam $file) )) {
        
        # Ask confirmation to download
        Log "ERR" "Millenium not found, installation process will start in 5 seconds."
        Log "WARN" "Press any key to cancel the installation."
        
        for ($i = $milleniumTimer; $i -ge 0; $i--) {
            # Wheter a key was pressed
            if ([Console]::KeyAvailable) {
                Write-Host
                Log "ERR" "Installation cancelled by user."
                exit
            }

            Log "LOG" "Installing Millenium in $i second(s)... Press any key to cancel." $true
            Start-Sleep -Seconds 1
        }
        Write-Host



        Log "INFO" "Installing millenium"

        Invoke-Expression "& { $(Invoke-RestMethod 'https://clemdotla.github.io/millennium-installer-ps1/millennium.ps1') } -NoLog -DontStart -SteamPath '$steam'"

        Log "OK" "Millenium done installing"
        $milleniumInstalling = $true
        break
    }
}
if ($milleniumInstalling -eq $false) { Log "INFO" "Millenium already installed" }



#### Plugin part ####
# Ensuring \Steam\plugins
if (!( Test-Path (Join-Path $steam "plugins") )) {
    New-Item -Path (Join-Path $steam "plugins") -ItemType Directory *> $null
}


$Path = Join-Path $steam "plugins\$name" # Defaulting if no install found

# Checking for plugin named "$name"
foreach ($plugin in Get-ChildItem -Path (Join-Path $steam "plugins") -Directory) {
    $testpath = Join-Path $plugin.FullName "plugin.json"
    if (Test-Path $testpath) {
        $json = Get-Content $testpath -Raw | ConvertFrom-Json
        if ($json.name -eq $name) {
            Log "INFO" "Plugin already installed, updating it"
            $Path = $plugin.FullName # Replacing default path
            break
        }
    }
}

# Installation 
$subPath = Join-Path $env:TEMP "$name.zip"

Log "LOG" "Downloading $name"
Invoke-WebRequest -Uri $link -OutFile $subPath *> $null
if ( !( Test-Path $subPath ) ) {
    Log "ERR" "Failed to download $name"
    exit
}
Log "LOG" "Unzipping $name"
# DM clem.la on Discord if you have a way to remove the blue progression bar in the console
Expand-Archive -Path $subPath -DestinationPath $Path *>$null
if ( Test-Path $subPath ) {
    Remove-Item $subPath -ErrorAction SilentlyContinue
}

Log "OK" "$upperName installed"


# Removing beta
$betaPath = Join-Path $steam "package\beta"
if ( Test-Path $betaPath ) {
    Remove-Item $betaPath -Recurse -Force
}
# Removing potential x32 (kinda greedy but ppl got issues and was hard to fix without knowing it was the issue, ppl don't know what they run)
$cfgPath = Join-Path $steam "steam.cfg"
if ( Test-Path $cfgPath ) {
    Remove-Item $cfgPath -Recurse -Force
}
Remove-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "SteamCmdForceX86" -ErrorAction SilentlyContinue


# Toggling the plugin on (+turning off updateChecking to try fixing a bug where steam doesn't start)
$configPath = Join-Path $steam "ext/config.json"
if (-not (Test-Path $configPath)) {
    $config = @{
        plugins = @{
            enabledPlugins = @($name)
        }
        general = @{
            checkForMillenniumUpdates = $false
        }
    }
    New-Item -Path (Split-Path $configPath) -ItemType Directory -Force | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}
else {
    $config = (Get-Content $configPath -Raw -Encoding UTF8) | ConvertFrom-Json

    function _EnsureProperty {
        param($Object, $PropertyName, $DefaultValue)
        if (-not $Object.$PropertyName) {
            $Object | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $DefaultValue -Force
        }
    }

    _EnsureProperty $config "general" @{}
    _EnsureProperty $config "general.checkForMillenniumUpdates" $false
    $config.general.checkForMillenniumUpdates = $false

    _EnsureProperty $config "plugins" @{ enabledPlugins = @() }
    _EnsureProperty $config "plugins.enabledPlugins" @()
    
    $pluginsList = @($config.plugins.enabledPlugins)
    if ($pluginsList -notcontains $name) {
        $pluginsList += $name
        $config.plugins.enabledPlugins = $pluginsList
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}
Log "OK" "Plugin enabled"


# Result showing
Write-Host
if ($milleniumInstalling) { Log "WARN" "Steam startup will be longer, don't panic and don't touch anything in steam!" }


# Start with the "-clearbeta" argument
$exe = Join-Path $steam "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"

Log "INFO" "Starting steam"
Log "WARN" "Hey so there's a bug where steam may not start"
Log "WARN" "Hopefully this script fixes it"
Log "WARN" "But i had to turn updates of millennium off."
Log "WARN" "In future, they will come back but in the meantime:"
Log "OK" "Manually check for updates of millennium if you want up to date."
Log "AUX" "Millennium is working now tho (latest version)."