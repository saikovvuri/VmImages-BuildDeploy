# Building Azure VM images using Packer and Powershell DSC

Repo that can be used to automate the process of building Azure VM images (using Packer and Powershell DSC) and then using the generated images to spin up single VMs or scalesets in Azure. 

[![Build status](https://sdrk.visualstudio.com/VmImage-Packer-Powershell/_apis/build/status/Packer%20Image%20Build)](https://sdrk.visualstudio.com/VmImage-Packer-Powershell/_build/latest?definitionId=55)

## Content Details

Primary folder is "packer-win2019-IIS-Php". It has the following contents

1. packer template
2. powershell dsc script
3. packer dsc provisioner, plugin that needs to reside alongside the packer exe file
4. packer exe file
..* since packer should be able to locate the packer dsc provisioner so 2 options are download both packer exe and provisioner exe to a known location in the repo and modify the PATH variable to use this version of packer exe
--* or use a self-hosted agent and set up the environment accordingly
5. Build yaml for someone to base their build pipeline of

## Future Work

1. Try out Azure Image Builder Service that uses packer behind the scene
2. Try out Azure Shared Image Gallery Service to store the generated images

## Acknowledgements

Greatly appreciate the below blogs posts for the insight and guidance

[Sam Cogan guideline on Packer Images + Azure Devops](https://samcogan.com/building-packer-images-with-azure-devops/)

[Arinam Hazra blog post on simple image automation with packer](https://arindamhazra.com/create-azure-windows-vm-image-with-packer-and-powershell/)

