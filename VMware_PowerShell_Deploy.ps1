# Import Core VMware Module
Import-Module -Name VMware.VimAutomation.Core
# Import Module for working with distributed switches
Import-Module -Name VMware.VimAutomation.Vds
Write-Host "*************PHASE I of III*****************"
Write-Host "*************Information Gather and VM Deployment*****************"
Write-Host "Current user" $env:USERDNSDOMAIN"\"$env:USERNAME
# Generate random number for use in customization spec naming scheme
$randomgen = Get-Random -Minimum 1000 -Maximum 100000
# Prompt for credentials to connect to vCenter
$myCred = Get-Credential -Message 'Provide vCenter Credentials '
# Specify name for vCenter Server#
$vcServer = Read-Host "Enter vCenter FQDN or IP Address"
Write-Host "Using vCenter Server $vcServer"
# Instantiate connection to vCenter Server
Connect-VIServer -Server $vcServer -Protocol https -Credential $myCred
# Asterisks Delimeter for reuse
$asterdelim = "***********************************************"
# String to populate notes field for VM
$notes = Read-Host "Enter VM Notes"
# Set DHCP Server of local deployment
$dhcpsite = Read-Host "Enter 3 Letter Site"
# Add code to select site DHCP Server
$dhcpServer = "$dhcpsite-dhcp-1.company.pri"
$checkdhcponline = Test-Connection -ComputerName $dhcpServer -Quiet
Write-Host "Is DHCP Server Online..." $checkdhcponline
# Specify Operating System Host Name
$osHostname = Read-Host "Enter OS Guest Host Name"
# Specify Name of VMware VM Name
$vmwareName = Read-Host "Enter VMware VM Display Name"
# Specify Customization Spec Name
Write-Host $asterdelim
Get-OSCustomizationSpec | Sort-Object $_.Name | Format-Table Name,LastUpdate
Write-Host $asterdelim
$specName = Read-Host "Enter Customization Spec Name (Be Exact)"
# Specify the cluster where the VM will live
$clusterName = Read-Host "Enter VMware Cluster Name"
$targetCluster = Get-Cluster -Name $clusterName
# Specify VM Template name
$template = Read-Host "Enter VM Template Name (Be Exact)"
$templateFetch = Get-Template -Name $template
# Define string for TempSpec name
$tempspecname = "TempSpec$randomgen"
# Defines a temporary customization spec, to alter guest OS hostname
New-OSCustomizationSpec -Spec $specName -Type NonPersistent -Name $tempspecname
# Set parameters of newly defined 'temp' customiztion spec'
Set-OSCustomizationSpec -Spec $tempspecname -NamingScheme:fixed -NamingPrefix $osHostname
# TODO: Specify Name of Datastore Cluster where VM will live#<---Temporarily commented - Use only for DS clusters, not single datastores
# $dsCluster = Read-Host "Enter Name of Datastore Cluster"
# $datastoreClusterFetch = Get-DatastoreCluster -Name $dsCluster
# Specify Name of Datastore where VM will live#
$dstore = Read-Host "Enter Name of Datastore"
$datastoreFetch = Get-Datastore -Name $dstore
# Specify amount of memory for the VM, in Gigabytes#
$memorySize = Read-Host "Enter Memory Size in Gigabytes (eg. '8')"

# Specify vCPU count#
# Also, confirm that vCPU count is an acceptable number in base 2
DO
{
$cpuCount = Read-Host "Enter vCPU Count (eg. '2')"
$cpuCountMod = ($cpuCount % 2)
if ($cpuCountMod -eq 0 -and $cpuCount -gt 1)
        {Write-Host "CPU divisor is good, continuing - $cpuCount"} 
            else {Write-Host "Please ensure the CPU count is divisible by 2 and greather than 1"}
}
Until ($cpuCountMod -eq 0 -and $cpuCount -gt 1)
# TODO: Add logic to split cores per socket being mindful of numa performance implications going across the qpi
# Specify disk provisioning parameter, thin, thick, etc#
# Below is not leveraged yet
# TODO: Specify disk format
$diskStorageFormat = 'Thin'
# Specify VDSwitch name that contains the relevant port group for the VM#
$vdSwitch = Read-Host "Enter Name of VD Switch (Exact)"
$vdSwitchFetch = Get-VDSwitch -Name $vdSwitch
# Specify the VD port group that the VM will be attached to#
$vdPortGroupName = Read-Host "Enter VDS Port Group Name (Exact)"
$vdPortGroup = Get-VDPortgroup -Name $vdPortGroupName -VDSwitch $vdSwitchFetch
# Deploy VM, using all parameters previously defined
Write-Host "***Confirm VM Parameters***"
Write-Host "VM Name$vmwareName"
Write-Host "Template$templateFetch"
Write-Host "VM Cluster$targetCluster"
$tempSpecParams = Get-OSCustomizationSpec -Name $tempspecname
Write-Host "VM Notes$notes"
Write-Host "Datastore Name$datastoreFetch"
Read-Host "Press any key to continue the VM deployment"
Read-Host "Are you sure you want to deploy? If not, break out now..."
New-VM -Name $vmwareName -Template $templateFetch -ResourcePool $targetCluster -OSCustomizationSpec $tempspecname -Notes $notes -Confirm -Datastore $datastoreFetch
# Sleep thread for x seconds, to allow vCenter time to close out VM deployment
Write-Host "Sleeping for 10 Seconds to allow VM to finalize..."
# Specify sleep time, in seconds
Start-Sleep -Seconds 10
# Now apply the VM resource parameters that were previously defined
Set-VM -VM $vmwareName -MemoryGB $memorySize -NumCpu $cpuCount -CoresPerSocket $cpuCount -Confirm
# Sleep thread for 5 seconds, to allow vCenter time to close out VM reconfiguration
Start-Sleep -Seconds 5
# Get network adapters for newly created VM, store as an object
$networkAdapter = Get-VM -Name $vmwareName | Get-NetworkAdapter
# Assign network adapter for VM to the dvSwitch and Port Group previously defined
Set-NetworkAdapter -NetworkAdapter $networkAdapter -Portgroup $vdPortGroup -Confirm
# Confirm a power on event
Read-Host "Press any key to power on the VM..."
# Power on the VM, with confirmation
Start-VM -VM $vmwareName -Confirm

# *************PHASE II*****************
Write-Host "*************PHASE II of III*****************"
$adminCredentials = Get-Credential -Message "Enter administrative account credentials"
Write-Host "Sleeping for 8 minutes, to allow time for spec to push..."
# This can be modified accordingly based on the speed of your environment
1..8 | ForEach-Object {Start-Sleep 60; Write-Host $_ Min. Passed}
Write-Host "Completed sleep for 8 minutes... Now testing connection"
do {$testConn = Test-Connection -ComputerName $osHostname -Quiet} until ($testConn)
Read-Host "If the above test failed, please ensure the node is online..."
Read-Host "Press any key to continue with the next phase of deployment..."
Read-Host "Please note, that this PowerShell session should be running under your admin_ security context, please confirm below"
Write-Host "Current user" $env:USERDNSDOMAIN"\"$env:USERNAME
Write-Host "If the current context is not running as a user with server administrator rights, you may soon encounter failures"
# Convert DHCP Lease to IPv4 Reservation
$vmIpAddress = (Get-VM -Name $vmwareName).Guest.IPAddress | Select-Object -First 1
Read-Host "Press any key to convert $osHostname with IP $vmIpAddress, an IPv4 Lease, to a Reservation..."
Get-DhcpServerv4Lease -ComputerName $dhcpServer -IPAddress $vmIpAddress | Add-DhcpServerv4Reservation -ComputerName $dhcpServer -Confirm
Write-Host "DHCP reservation completed for $osHostname"
Get-DhcpServerv4Reservation -ComputerName $dhcpServer -IPAddress $vmIpAddress |Format-Table -AutoSize -Property IPAddress,Name
# Create security groups in AD for Local Admins
Read-Host "Press any key to continue creating Domain Security Groups"
$domain = "company.pri"
$domGroupName = "WH ${osHostname}_Administrators"
$fqdnOsHostname = "$osHostname.company.pri"
New-ADGroup -Server:AME-DCT-PRD01 -Name $domGroupName -Description "Local Administrator access to $serverName" -Path "OU=Groups,OU=Company,DC=company,DC=local" -GroupCategory:Security -GroupScope:Global -Confirm -Credential $adminCredentials
Write-Host "Group $domGroupName was created in domain $domain"
Read-Host "Press any key to add $domGroupName to the local administrators on $osHostname"
Write-Host "Sleeping 30 seconds to allow time for intra-site replication of new group"
Start-Sleep -Seconds 30
Write-Host "Getting AD group"
Get-ADGroup -Server:AME-DCT-PRD01 -Identity $domGroupName
# Manually Sync the AD Obect
# TODO: Add code to sync the object within the domain
# To work around this issue, run the script on a system within the site of deployment
# i.e. run this on an DATACENTER-A system if deploying a VM at DATACENTER-A
# Add security group to local administrators on the server
# Set name of local admin group on target systems
$localgroup = "Administrators"
([ADSI]"WinNT://$fqdnOsHostname/$localgroup,group").psbase.Invoke("Add",([ADSI]"WinNT://$domain/$domGroupName").path)
Write-Host "Completed adding AD group to the Local Server Administrators group"

# Verify DNS Name is resolving by testing the connection via fqdn
Write-Host "Confirming that DNS is good"
Test-Connection -ComputerName $fqdnOsHostname -Count 1

# *************PHASE III*****************
Write-Host "*************PHASE III of III*****************"

# Add node to SolarWinds using SW SDK
Write-Host "Be sure to manually add $osHostname to your monitoring tool of choice (SolarWinds, PRTG, etc)"

# TODO: Move into correct OU in Active Directory

# TODO: Create ticket to perform security scan of server, this could be an SMTP or API call to ServiceNow or similar ITSM Platform