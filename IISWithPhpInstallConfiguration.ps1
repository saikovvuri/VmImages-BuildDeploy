Install-Module -Name xWebAdministration
Install-Module xPSDesiredStateConfiguration

configuration PhpOnIis
{
     param
    (
        [Parameter(Mandatory = $true)]
        [string] $PackageFolder,
        [Parameter(Mandatory = $true)]
        [string] $PhpDownloadUri,
        [Parameter(Mandatory = $true)]
        [string] $VcplusRedistDownloadUri,
        [Parameter(Mandatory = $true)]
        [String] $PhpInstallPath
        
    )

    Import-DscResource -ModuleName xPSDesiredStateConfiguration
    Import-DscResource -ModuleName xWebAdministration
    

    $features = @("Web-Server",
	"Web-Mgmt-Tools",
	"web-Default-Doc",
	"Web-Dir-Browsing",
	"Web-Http-Errors",
	"Web-Static-Content",
	"Web-Http-Logging",
	"web-Stat-Compression",
	"web-Filtering",
	"web-CGI",
	"web-ISAPI-Ext",
	"web-ISAPI-Filter"
    )

    $dependsOn = @()

    $features | ForEach-Object -Process {
	    WindowsFeature $_ {
		    Name   = $_
		    Ensure = "Present" 
	    }
	    $dependsOn += "[WindowsFeature]$($_)"
    }

     @(
	    ".NET v2.0" ,
	    ".NET v2.0 Classic",
	    ".NET v4.5",
	    ".NET v4.5 Classic",
	    "Classic .NET AppPool",
	    "DefaultAppPool"
    ) | ForEach-Object -Process {
	    xWebAppPool "Remove-$($_.ToString().Replace(" ","").Replace(".",""))"
	    {
		    Name      = $_
		    Ensure    = "Absent"
		    DependsOn = $dependsOn
	    }
    }

    xWebSite RemoveDefaultWebSite
    {
	    Name         = "Default Web Site"
	    PhysicalPath = "C:\inetpub\wwwroot"
	    Ensure       = "Absent"
        DependsOn    = $dependsOn
    }

    # Download and install Visual C ++ from chocolatey.org
    Package vcRedist
    {
        Path = $VcplusRedistDownloadUri
        ProductId = "EEA66967-97E2-4561-A999-5C22E3CDE428"
        Name = "Microsoft Visual C++ 2015-2019"
        Arguments = "/install /passive /norestart"
    }

    xScript EnableTLS12
    {
        SetScript = {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol.toString() + ', ' + [Net.SecurityProtocolType]::Tls12
        }
        TestScript = {
            return ([Net.ServicePointManager]::SecurityProtocol -match 'Tls12')
        }
        GetScript = {
            return @{
            Result = ([Net.ServicePointManager]::SecurityProtocol -match 'Tls12')
            }
        }
    }

    $phpZip = Join-Path $PackageFolder "php.zip"

    # Make sure the PHP archine is in the package folder
    xRemoteFile phpArchive
    {
        uri = $PhpDownloadUri
        DestinationPath = $phpZip
        DependsOn = @("[xScript]EnableTLS12")
    }

    # Make sure the content of the PHP archive are in the PHP path
    Archive php
    {
        Path = $phpZip
        Destination  = $PhpInstallPath       
    }

    # Make sure the php.ini is renamed in the Php folder
    File PhpIni
    {
        SourcePath = "$($PhpInstallPath)\php.ini-development"
        DestinationPath = "$($PhpInstallPath)\php.ini"
        DependsOn = @("[Archive]PHP")
        MatchSource = $true
    }



     # Make sure the php cgi module is registered with IIS
    <# xIisModule phpHandler
    {
        Name = "phpFastCgi"
        Path = "$($PhpInstallPath)\php-cgi.exe"
        RequestPath = "*.php"
        Verb = "*"
        Ensure = "Present"
        ModuleType = "FastCgiModule"
        DependsOn = @("[Package]vcRedist","[File]PhpIni")
        
    } #>

    # Make sure the php binary folder is in the path
    Environment PathPhp
    {
        Name = "Path"
        Value = ";$($PhpInstallPath)"
        Ensure = "Present"
        Path = $true
        DependsOn = "[Archive]PHP"
    }
}

#Create the MOF
PhpOnIis -PackageFolder "C:\packages" `
    -PhpDownloadUri  "https://windows.php.net/downloads/releases/php-7.4.4-nts-Win32-vc15-x64.zip"`
    -VcplusRedistDownloadUri "https://aka.ms/vs/16/release/vc_redist.x64.exe" `
    -PhpInstallPath "C:\php"

#Apply the configuration
Start-DscConfiguration -Path .\PhpOnIis -Wait -Verbose -Force

#Module Mapping not working with xIisModule
New-WebHandler -Name "PHP-FastCGI" -Path "*.php" -Verb "*" -Modules "FastCgiModule" -ScriptProcessor "c:\php\php-cgi.exe" -ResourceType Either
    