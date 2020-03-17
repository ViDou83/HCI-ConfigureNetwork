[CmdletBinding(DefaultParameterSetName = "NoParameters")]
param(
    [Parameter(Mandatory = $false, ParameterSetName = "ConfigurationFile")]
    [String] $ConfigurationDataFile = ".\configfiles\HCI-NetworkConfig.psd1"
)    

# Script version, should be matched with the config files
$ScriptVersion = "2.0"

#Validating passed in config files
if ($psCmdlet.ParameterSetName -eq "ConfigurationFile") 
{
   Write-host "Using configuration file passed in by parameter."    
    $configdata = [hashtable] (iex (gc $ConfigurationDataFile | out-string))
}
elseif ($psCmdlet.ParameterSetName -eq "ConfigurationData") 
{
   Write-host "Using configuration data object passed in by parameter."    
    $configdata = $configurationData 
}

if ($Configdata.ScriptVersion -ne $scriptversion) 
{
   Write-host "Configuration file $ConfigurationDataFile version $($ConfigData.ScriptVersion) is not compatible with this version of SDN express."
   Write-host "Please update your config file to match the version $scriptversion example."
    return
}

winrm set winrm/config/client '@{TrustedHosts="*"}'

$LocalAdminCred = Get-Credential $configdata.LocalAdmin -Message "Please provide password for $($configdata.localAdmin) account"
$LocalAdminPassword = $LocalAdminCred.GetNetworkCredential().Password

foreach ( $node in $configdata.nodes)
{
    $username=$configdata.LocalAdmin
    $password= $LocalAdminPassword | ConvertTo-SecureString -asPlainText -Force
    $credential =  New-Object System.Management.Automation.PSCredential("$node\$username", $password )

    Write-Host -ForegroundColor Yellow "Configuring Networking on $node"
    invoke-command -ComputerName $node -Credential $credential {
        $configdata=$args[0]
        ################
        #########
        #####   Checking pNICs
        #########
        ################
        Write-Host -ForegroundColor Yellow "Checking if pNICs are existing and not bound to any vSwitch or holding TCPIP config"
        $pNICs=$configdata.pNICs
        foreach( $pNIC in $pNICs)
        {
            if (! (get-netadapter $pNIC.Name -ea SilentlyContinue ))
            {
                throw "$($pNIC.Name) cannot be found. Please check the name of the interface. Rename-NetAdapter to change his name to $pNIC"
            }
            else
            {
                $NicGuid=((Get-NetAdapter $pNIC.Name).InterfaceGuid).replace("{","").replace("}","")

                Write-Host -ForegroundColor Yellow "Checking that pNICs are not bound to any vSwitch"
                $CurrentVswitches=Get-VMSwitch -ea SilentlyContinue
                foreach( $CurrentvSwitch in $CurrentVswitches)
                {
                    $NicGuids=$CurrentvSwitch.NetAdapterInterfaceGuid
                    foreach( $Guid in $NicGuids )
                    {
                        if ( $Guid -eq $NicGuid)
                        {
                            throw "$($pNIC.Name) is already bound to vSwitch $($CurrentvSwitch.Name). Please investigate!"
                        }
                    }
                }
                
                Write-Host -ForegroundColor Green "Reseting NetAdapterAdvancedProperty for $($pNIC.Name)"
                reset-netadapteradvancedproperty $pNIC.Name -DisplayName *        
            }
            #
            if ( $pNIC.VmmqEnabled )
            {
                Write-Host -ForegroundColor Green "Enabling VMMQ on $($pNIC.Name)"
                Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*RssOnHostVPorts" -RegistryValue 1
                Write-Host -ForegroundColor Green "Configuring $($pNIC.NumberOfReceiveQueues) Queues on $($pNIC.Name)"
                Set-NetAdapterRss $pNIC.Name -NumberOfReceiveQueues $pNIC.NumberOfReceiveQueues
            }
            else
            {
                Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*RssOnHostVPorts" -RegistryValue 0
            }
        }

        ################
        #########
        #####   vSwitch configuration
        #########
        ################
        $index=0
        $vSwitches=$configdata.vSwitches
        foreach( $vSwitch in $vSwitches)
        {
            if ( Get-VMSwitch $vSwitch.Name -ea SilentlyContinue )
            {
                throw "$($vSwitch.Name) is already existing. Please do cleanup first"
            }
            else 
            {
                Write-Host -ForegroundColor Yellow "Creating vSwitch $($vSwitch.Name)"
                New-VmSwitch -Name $vSwitch.name -EnableEmbeddedTeaming $vSwitch.SetEnabled `
                    -NetAdapterName $vSwitch.pNICs.Name -AllowManagementOS $vSwitch.MgmtOS
                if ( ! (Get-VMSwitch $vSwitch.Name -ea SilentlyContinue) )
                {
                    throw "$($vSwitch.Name) creation has failed. Please investigate"
                }
                #Creating host vNIC
                foreach( $HOSTvNIC in $vSwitch.HostvNICs )
                {
                    Write-Host -ForegroundColor Green "Adding Host vNIC $($HOSTvNIC.Name)"
                    Add-VMNetworkAdapter -ManagementOS -Name $HOSTvNIC.Name -SwitchName $vSwitch.Name
                    #To be sure that the vNIC is well created
                    sleep 10
                    $NIC = Get-NetAdapter "*$($HOSTvNIC.Name)*"
                    
                    Write-Host -ForegroundColor Green "Configure Host vNIC $($HOSTvNIC.Name) IP Configuration $($HOSTvNIC.IpAddr)/$($HOSTvNIC.CIDR)"
                    $NIC | New-NetIPAddress -IpAddress $HOSTvNIC.IpAddr -PrefixLength $HOSTvNIC.CIDR -DefaultGateway $HOSTvNIC.GW | Out-Null
                    if ( $HOSTvNIC.DNS )
                    {
                        Write-Host -ForegroundColor Green "Configure Host vNIC $($HOSTvNIC.Name) DNS Srv=$($HOSTvNIC.DNS)"
                        $vNIC | Set-DnsClientServerAddress -ServerAddresses $HOSTvNIC.DNS
                    }

                    if ( $HOSTvNIC.VmmqEnabled )
                    {
                        Write-Host -ForegroundColor Green "Enabling VMMQ on vNIC $($HOSTvNIC.Name)"
                        Get-VMNetworkAdapter -ManagementOS $HOSTvNIC.Name | Set-VMNetworkAdapter -VmmqEnabled $HOSTvNIC.VmmqEnabled
                    }
                    else
                    {
                        Get-VMNetworkAdapter -ManagementOS $HOSTvNIC.Name | Set-VMNetworkAdapter -VmmqEnabled $false   
                    }

                    if ( $HOSTvNIC.RDMAEnabled )
                    {
                        Write-Host -ForegroundColor Green "Enabling RDMA on vNIC $($HOSTvNIC.Name)"
                        $NIC | Enable-NetAdapterRdma 
                    }
                    else
                    {
                        $NIC | Disable-NetAdapterRdma 
                    }
                
                    Write-Host -ForegroundColor Green "Rss Config: forcing base proc to 2 for vNIC $($HOSTvNIC.Name)"
                    $NIC | Set-NetAdapterRss -BaseProcessorGroup 0 -BaseProcessorNumber 2

                    #### Configuring SwitchTeamMapping
                    Write-Host -ForegroundColor Green "Configuring VMNetworkAdapterTeamMapping for $($HOSTvNIC.Name) on  $($pNICs.Name[$index])"
                    Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName $HostvNIC.Name -ManagementOS `
                        -PhysicalNetAdapterName $pNICs.Name[$index]
                    $index++
                }
                #Checking TeamMapping
                Get-VMNetworkAdapter -All | Get-VMNetworkAdapterTeamMapping
            }
        }


        ################
        #########
        #####   RSS/VMQ/VMMQ Configuration
        #########
        ################
        $index=0
        if ( $configdata.AutoSyntheticAccelerationConfig )
        {
            Write-Host -ForegroundColor Yellow `
                "Configuring Synthetic Acceleration: vRSS/VMMQ/VMQ and so on based on NUMA topology and LPs numbers detected!"
            
            $LPs=0
            $NUMANode=Get-VMHostNumaNode
            foreach ( $NUMA in $NUMANode)
            {
                $LPs+=$NUMA.ProcessorsAvailability.count
            }

            Write-Host -ForegroundColor Green "Trying to pin each pNIC to a different Numa Node"
            foreach( $pNIC in $configdata.pNICs)
            {
                if ( $NUMANode.count -gt 1 )
                {
                    Set-NetAdapterAdvancedProperty -Name $pNIC.Name -RegistryKeyword '*NumaNodeId' -RegistryValue $NUMANode.NodeId[$Index]
                    #
                    if ( $NUMANode.NodeId[$Index+1] -lt $NumaNode.Count ){ $index++ }
                }
                get-NetAdapterRss $pNIC.Name | ft
                
                Write-Host -ForegroundColor Green "VMQ Config: Using all LPs available except LP=0"
                Set-NetAdapterVMQ $pNIC.Name -BaseProcessorGroup 0 -BaseProcessorNumber 2 -MaxProcessors $($LPs/2)
                get-NetAdapterVMQ $pNIC.Name | ft

                Write-Host -ForegroundColor Green "Rss Config: Setting NumberOfReceiveQueues to $($pNIC.NumberOfReceiveQueues)"
                Set-NetAdapterRss $pNIC.Name -NumberOfReceiveQueues $pNIC.NumberOfReceiveQueues
            }
        }
    } -ArgumentList $configdata[$node]
}

################
#########
#####   Configuring DCB
#########
################
if ( $configdata.DCBEnabled )
{
    Write-Host -ForegroundColor Yellow "Configuring DCB"
    if ( ! (Get-WindowsFeature Data-Center-Bridging).Installed )
    {
        #Install DCB
        Install-WindowsFeature -Name Data-Center-Bridging
    }
    #Set policy for Cluster Heartbeats
    New-NetQosPolicy "Cluster" -Cluster -PriorityValue8021Action 7    
    New-NetQosTrafficClass "Cluster" -Priority 7 -BandwidthPercentage 1 -Algorithm ETS
    #Set policy for SMB-Direct 
    New-NetQosPolicy "SMB" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3
    Enable-NetQosFlowControl -priority 3
    New-NetQosTrafficClass "SMB" -priority 3 -bandwidthpercentage 50 -algorithm ETS

    foreach( $pNIC in $pNICs)
    {
        #Enabling QoS at NetAdapter Level
        Enable-NetAdapterQos -InterfaceAlias $pNIC.Name
        #Block DCBX settings from the switch
        Set-NetQosDcbxSetting -InterfaceAlias $pNIC.Name -Willing $False
        # Disable flow control (Global Pause) on physical adapters
        Set-NetAdapterAdvancedProperty -Name $pNIC.Name -RegistryKeyword "*FlowControl" -RegistryValue 0
    }

    # Set policy for the rest of the traffic 
    New-NetQosPolicy "DEFAULT" -Default -PriorityValue8021Action 0
    Disable-NetQosFlowControl -priority 0,1,2,4,5,6,7

    #Checking Config
    Get-NetQosFlowControl
    foreach( $pNIC in $pNICs)
    {
        Get-NetAdapterQos -Name $pNIC.Name
    }
}

################
#########
#####   Checking cluster nodes connectivity 
#########
################
Write-Host -ForegroundColor Yellow "Checking cluster nodes connectivity"
foreach ( $node in $configdata.nodes)
{
    $username=$configdata.LocalAdmin
    $password= $LocalAdminPassword | ConvertTo-SecureString -asPlainText -Force
    $credential =  New-Object System.Management.Automation.PSCredential("$node\$username", $password )

    invoke-command -ComputerName $node -Credential $credential {
        $configdata=$args[0]
        foreach ( $node in $configdata.nodes)
        {          
            if ( $node -ne $env:COMPUTERNAME)
            {
                foreach( $vNIC in $configdata[$node].vSwitches.HostvNICs)
                {
                    Write-Host -ForegroundColor Yellow "Checking networking connectivy from $env:computername to $node/$($vNIC.IpAddr)"
                    if ( Test-Connection $vNIC.IpAddr ){
                        Write-Host -ForegroundColor Green "Ping is OK!"
                    }
                    else 
                    {
                        Write-Host -ForegroundColor Red "Ping FAILED!"    
                    }
                }
            }
        }
    } -ArgumentList $configdata
}