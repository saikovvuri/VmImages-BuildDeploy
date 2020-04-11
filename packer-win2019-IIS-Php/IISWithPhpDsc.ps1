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

    # Ensure packagefolder exists
    File packageFolderExists
    {
        Ensure      = "Present"
        Type        = "Directory"
        DestinationPath = $PackageFolder
    }

    # Ensure php install location exists
    File phpInstallPathExists
    {
        Ensure      = "Present"
        Type        = "Directory"
        DestinationPath = $PhpInstallPath
    }

    # Download and install Visual C ++ from chocolatey.org
    Package vcRedist
    {
        Path = $VcplusRedistDownloadUri
        ProductId = "EEA66967-97E2-4561-A999-5C22E3CDE428"
        Name = "Microsoft Visual C++ 2015-2019"
        Arguments = "/install /passive /norestart"
    }

    # Enable TLS 1.2
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

    # Make sure the PHP archine is in the package folder
    xRemoteFile phpArchive
    {
        uri = $PhpDownloadUri
        DestinationPath = "$($PackageFolder)\php.zip"
        DependsOn = @("[xScript]EnableTLS12", "[File]packageFolderExists")
    }

    # Make sure the content of the PHP archive are in the PHP path
    Archive php
    {
        Path = "$($PackageFolder)\php.zip"
        Destination  = $PhpInstallPath
        DependsOn = @("[File]phpInstallPathExists")       
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
    Script FixIisModule {
        
        GetScript = {                
		    return @{
			    Result = ""
		    }
	    }
        TestScript = {
            Import-Module WebAdministration
		    $fastCgi = Get-WebHandler -Name "PHP-FastCGI"
		    return ($null -ne $fastCgi)                
	    }
        SetScript = {
            Import-Module WebAdministration
            $phpCgiPath = "$($using:PhpInstallPath)\php-cgi.exe"
            New-WebHandler -Name "PHP-FastCGI" -Path "*.php" -Verb "*" -Modules "FastCgiModule" -ScriptProcessor $phpCgiPath -ResourceType Either
        }
        DependsOn = @("[Package]vcRedist","[File]PhpIni")
    }

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