Param(
	[Parameter(Mandatory=$true)]
	[String]$subscriptionId,
	[Parameter(Mandatory=$true)]
        [String]$imageNamePrefix,
        [Parameter(Mandatory=$false)]
	[String]$location = "northcentralus",
        [Parameter(Mandatory=$false)]
        [String]$imageSku = "2016-Datacenter"
)

# Function to create template definition json file for Packer
Function Create-JsonTemplate()
{
    Try{	
    $input = @"
    {
        "builders": [{
            "type": "azure-arm",
        
            "client_id": "$($applicationId)",
            "client_secret": "$($applicationSecret)",
            "tenant_id": "$($tenantId)",
            "subscription_id": "$($subscriptionId)",
        
            "managed_image_resource_group_name": "$($azResourceGroupName)",
            "managed_image_name": "$($azImageName)",
        
            "os_type": "Windows",
            "image_publisher": "MicrosoftWindowsServer",
            "image_offer": "WindowsServer",
            "image_sku": "$($imageSku)",

            "communicator": "winrm",
            "winrm_use_ssl": true,
            "winrm_insecure": true,
            "winrm_timeout": "20m",
            "winrm_username": "packer",

        
            "azure_tags": {
                "CreationDate": "$((Get-Date).ToString("dd-MMM-yyyy"))",
                "ImageOS": "$($imageSku)",
                "Owner": "Avengers"
            },
        
            "location": "$($location)",
            "vm_size": "Standard_DS2_v2"
          }],
          "provisioners": [{
            "type": "powershell",
            "inline": [
              "Set-ItemProperty -path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa\\Kerberos\\Parameters' -Name MaxTokenSize -value 48000 -type DWord -Force",
              "Set-ItemProperty -path 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects' -Name VisualFXSetting -value 2 -type DWord -Force",
              "Set-ItemProperty -path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Lsa\\Kerberos\\Parameters' -Name MaxTokenSize -value 48000 -type DWord -Force",
              "Disable-WindowsErrorReporting",
              "& C:\\Windows\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
              "while(1 -eq 1) { $imageState=Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($($imageState.ImageState) -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $($imageState.ImageState); Start-Sleep -s 10  } else { break } }"
            ]
          }]
    }	
"@ 
$input | Out-File $Global:jsonTemplateFile -Encoding ascii
    }
    Catch
    {
        Write-Host "ERROR : $_" -Foregroundcolor Red
        Exit
    }
}

# Function to create Image using Packer
Function Create-Image(){
    Try{
        powershell packer build $Global:jsonTemplateFile
    }
    Catch
    {
        Write-Host "ERROR : $_" -Foregroundcolor Red
        Exit
    }
}

# Function to remove resources created during the image creation process
Function Cleanup-Resources(){
    Try{
        Write-Host "Deleting Service Principal used by Packer"
        Remove-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName 'Contributor' -Scope "/subscriptions/$($subscriptionId)"
        Remove-AzADServicePrincipal -ApplicationId $applicationId -Force

        Write-Host "Deleting Template JSON file"
        if(Test-Path -Path $Global:jsonTemplateFile){
            Remove-Item -Path $Global:jsonTemplateFile -Force
        }
    }
    Catch{
        Write-Host "ERROR : $_" -Foregroundcolor Red
    }
}

$Global:jsonTemplateFile = "$($env:Temp)\image-template.json"
if(Test-Path $Global:jsonTemplateFile){Remove-Item -Path $Global:jsonTemplateFile -Force}

# Check if chocolatey is already installed on local system. If not, install.
$checkChoco = choco --version
if([String]::IsNullOrEmpty($checkChoco)){
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

# Check if Packer is already installed.If not, install using chocolatey
$checkPacker = packer --version
if([String]::IsNullOrEmpty($checkPacker)){
    choco install packer
}

# Login to Azure Account
Connect-AzAccount

$azContext = Set-AzContext -Subscription $subscriptionId
if([String]::IsNullOrEmpty($azContext)){
    Write-Host "Error: Azure Context has not been set.Either you don't have permission to the subscription or some other issue!" -Foregroundcolor Red
    Exit
}

if(!((Get-AzLocation | Select-Object -ExpandProperty Location).Contains($location))){
    Write-Host "Error: Location $($location) is not a valid Azure Region. Try again with correct Region!" -Foregroundcolor Red
    Exit
}

# Create a Resource Group  if it is not already there
$azResourceGroupName = "azure-image-store-rg"
if(!(Get-AzResourceGroup -Name $azResourceGroupName -ErrorAction SilentlyContinue)){
    New-AzResourceGroup -Name $azResourceGroupName -Location $location
}
$rgInfo = Get-AzResourceGroup -Name $azResourceGroupName

# Create a Service Principal to be used used by Packer and setting scope to the resource group only
$spInfo = New-AzADServicePrincipal -DisplayName "az-packer-image-create-sp-$((Get-Date).ToString("dd-MMM-yyyy-HHmmss"))" -Scope "/subscriptions/$($subscriptionId)" -EndDate (Get-Date).AddHours(3)
$applicationId = $spInfo.ApplicationId
$objectId = $spInfo.Id
$applicationSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($spInfo.Secret))
$tenantId = $azContext.Tenant.Id
$azImageName = "$($imageNamePrefix)-$($imageSku)-$((Get-Date).ToString("dd-MMM-yyyy"))"
$imgDetails = Get-AzImage -ResourceGroupName $azResourceGroupName -ImageName $azImageName -ErrorAction SilentlyContinue

if(!([String]::IsNullOrEmpty($imgDetails))){
    $azImageName = "$($azImageName)-$(-join ((65..90) + (97..122) | Get-Random -Count 6 | ForEach-Object {[char]$_}))"
}

Create-JsonTemplate 
Create-Image
$imgDetails = Get-AzImage -ResourceGroupName $azResourceGroupName -ImageName $azImageName -ErrorAction SilentlyContinue
if(!([String]::IsNullOrEmpty($imgDetails))){
    Write-Host "New Image $($imgDetails.Name) created successfully!" -ForegroundColor Green
}
else{
    Write-Host "Error: Something went wrong! Please try again!" -ForegroundColor Red
}
Cleanup-Resources