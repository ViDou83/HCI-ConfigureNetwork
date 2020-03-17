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
    Write-Host -ForegroundColor Yellow "########################################"
    Write-Host -ForegroundColor Yellow "#   Configuring Networking on $node"
    Write-Host -ForegroundColor Yellow "########################################"

    invoke-command -ComputerName $node -Credential $credential {
        $configdata=$args[0]
        ################
        #########
        #####   Checking pNICs
        #########
        ################
        Write-Host "- Checking if pNICs are existing and not bound to any vSwitch or holding TCPIP config"
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

                Write-Host "- Checking that pNICs are not bound to any vSwitch"
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
                
                Write-Host -ForegroundColor Yellow "Reseting NetAdapterAdvancedProperty for $($pNIC.Name)"
                reset-netadapteradvancedproperty $pNIC.Name -DisplayName *        
            }
            #
            if ( $pNIC.VmmqEnabled )
            {
                Write-Host -ForegroundColor Yellow "Enabling VMMQ on $($pNIC.Name)"
                Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*RssOnHostVPorts" -RegistryValue 1
                Write-Host -ForegroundColor Green "Configuring $($pNIC.NumberOfReceiveQueues) Queues on $($pNIC.Name)"
                Set-NetAdapterRss $pNIC.Name -NumberOfReceiveQueues $pNIC.NumberOfReceiveQueues
            }
            else
            {
                Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*RssOnHostVPorts" -RegistryValue 0
            }
            #RDMA mode iWARP or ROCe
            if ( $pNIC.RDMAEnabled)
            {
                Write-Host "+ Enabling RDMA/NetworkDirect on $($pNIC.Name)"
                Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*NetworkDirect" -RegistryValue 1
                if ( $pNIC.RDMAMode -eq "iWARP")
                {
                    Write-Host -ForegroundColor Yellow "+ Enabling iWARP on $($pNIC.Name)"
                    Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*NetworkDirectTechnology" -RegistryValue 1
                }
                elseif ( $pNIC.RDMAMode -eq "RoCE")
                {
                    Write-Host -ForegroundColor Yellow "+ Enabling iWARP on $($pNIC.Name)"
                    Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*NetworkDirectTechnology" -RegistryValue 3
                }
                elseif ( $pNIC.RDMAMode -eq "RoCEv2")
                {
                    Write-Host -ForegroundColor Yellow "+ Enabling iWARP on $($pNIC.Name)"
                    Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*NetworkDirectTechnology" -RegistryValue 4
                }
                else
                {
                    throw "$($pNIC.Name) bad RDMA/NetworkDirect specified in the config File. Valids are iWARP/RoCE/RoCEv2"
                }
            }
            #JumboFRames
            if ( $pNIC.JumboFrames )
            {
                Write-Host "+ Enabling JumboFrame 9K on $($pNIC.Name)"
                Set-NetAdapterAdvancedProperty $pNIC.Name -RegistryKeyword "*JumboPacket" -RegistryValue 9014
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
                Write-Host -ForegroundColor Yellow "########################################"   
                Write-Host -ForegroundColor Yellow "#    Creating vSwitch $($vSwitch.Name)"
                Write-Host -ForegroundColor Yellow "########################################"
        
                New-VmSwitch -Name $vSwitch.name -EnableEmbeddedTeaming $vSwitch.SetEnabled `
                    -NetAdapterName $vSwitch.pNICs.Name -AllowManagementOS $vSwitch.MgmtOS
                if ( ! (Get-VMSwitch $vSwitch.Name -ea SilentlyContinue) )
                {
                    throw "$($vSwitch.Name) creation has failed. Please investigate"
                }
                #Creating host vNIC
                foreach( $HOSTvNIC in $vSwitch.HostvNICs )
                {
                    Write-Host -ForegroundColor Yellow "+ Adding Host vNIC $($HOSTvNIC.Name)"
                    Add-VMNetworkAdapter -ManagementOS -Name $HOSTvNIC.Name -SwitchName $vSwitch.Name
                    #To be sure that the vNIC is well created
                    sleep 10
                    $NIC = Get-NetAdapter "*$($HOSTvNIC.Name)*"
                    
                    Write-Host -ForegroundColor Yellow "+ Configure Host vNIC $($HOSTvNIC.Name) IP Configuration $($HOSTvNIC.IpAddr)/$($HOSTvNIC.CIDR)"
                    $NIC | New-NetIPAddress -IpAddress $HOSTvNIC.IpAddr -PrefixLength $HOSTvNIC.CIDR -DefaultGateway $HOSTvNIC.GW | Out-Null
                    if ( $HOSTvNIC.DNS )
                    {
                        Write-Host -ForegroundColor Yellow "+ Configure Host vNIC $($HOSTvNIC.Name) DNS Srv=$($HOSTvNIC.DNS)"
                        $vNIC | Set-DnsClientServerAddress -ServerAddresses $HOSTvNIC.DNS
                    }

                    if ( $HOSTvNIC.VmmqEnabled )
                    {
                        Write-Host "+ Enabling VMMQ on vNIC $($HOSTvNIC.Name)"
                        Get-VMNetworkAdapter -ManagementOS $HOSTvNIC.Name | Set-VMNetworkAdapter -VmmqEnabled $HOSTvNIC.VmmqEnabled
                    }
                    else
                    {
                        Get-VMNetworkAdapter -ManagementOS $HOSTvNIC.Name | Set-VMNetworkAdapter -VmmqEnabled $false   
                    }

                    if ( $HOSTvNIC.RDMAEnabled )
                    {
                        Write-Host "+ Enabling RDMA on vNIC $($HOSTvNIC.Name)"
                        $NIC | Enable-NetAdapterRdma 
                    }
                    else
                    {
                        $NIC | Disable-NetAdapterRdma 
                    }
                    #JumboFrames
                    if ( $pNIC.JumboFrames )
                    {
                        Write-Host "+ Enabling JumboFrame 9K on $($HOSTvNIC.Name)"
                        $NIC | Set-NetAdapterAdvancedProperty -RegistryKeyword "*JumboPacket" -RegistryValue 9014
                    }
                
                    Write-Host -ForegroundColor Yellow "+ Rss Config: forcing base proc to 2 for vNIC $($HOSTvNIC.Name)"
                    $NIC | Set-NetAdapterRss -BaseProcessorGroup 0 -BaseProcessorNumber 2

                    #### Configuring SwitchTeamMapping
                    Write-Host -ForegroundColor Yellow "+ Configuring VMNetworkAdapterTeamMapping for $($HOSTvNIC.Name) on  $($pNICs.Name[$index])"
                    Set-VMNetworkAdapterTeamMapping -VMNetworkAdapterName $HostvNIC.Name -ManagementOS `
                        -PhysicalNetAdapterName $pNICs.Name[$index] | Out-Null
                    $index++
                }
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
            Write-Host -ForegroundColor Yellow "########################################"
            Write-Host -ForegroundColor Yellow `
                "Configuring Synthetic Acceleration: vRSS/VMMQ/VMQ and so on based on NUMA topology and LPs numbers detected!"
            Write-Host -ForegroundColor Yellow "########################################"
            
            $LPs=0
            $NUMANode=Get-VMHostNumaNode
            foreach ( $NUMA in $NUMANode)
            {
                $LPs+=$NUMA.ProcessorsAvailability.count
            }

            Write-Host -ForegroundColor Yellow "+ Trying to pin each pNIC to a different Numa Node"
            foreach( $pNIC in $configdata.pNICs)
            {
                if ( $NUMANode.count -gt 1 )
                {
                    Set-NetAdapterAdvancedProperty -Name $pNIC.Name -RegistryKeyword '*NumaNodeId' -RegistryValue $NUMANode.NodeId[$Index]
                    #
                    if ( $NUMANode.NodeId[$Index+1] -lt $NumaNode.Count ){ $index++ }
                }
                get-NetAdapterRss $pNIC.Name | ft
                
                Write-Host -ForegroundColor Yellow "+ VMQ Config: Using all LPs available except LP=0"
                Set-NetAdapterVMQ $pNIC.Name -BaseProcessorGroup 0 -BaseProcessorNumber 2 -MaxProcessors $($LPs/2)
                get-NetAdapterVMQ $pNIC.Name | ft

                Write-Host -ForegroundColor Yellow "+ Rss Config: Setting NumberOfReceiveQueues to $($pNIC.NumberOfReceiveQueues)"
                Set-NetAdapterRss $pNIC.Name -NumberOfReceiveQueues $pNIC.NumberOfReceiveQueues
            }
        }

        ################
        #########
        #####   Configuring DCB
        #########
        ################
        if ( $configdata.DCBEnabled )
        {

            Write-Host -ForegroundColor Yellow "########################################"
            Write-Host -ForegroundColor Yellow "#   Configuring DCB on $node"
            Write-Host -ForegroundColor Yellow "########################################"

            if ( ! (Get-WindowsFeature Data-Center-Bridging).Installed )
            {
                #Install DCB
                Install-WindowsFeature -Name Data-Center-Bridging
            }
            #Set policy for Cluster Heartbeats
            Write-Host -ForegroundColor Yellow "+ Creating Cluster NetQoSPolicy"
            New-NetQosPolicy "Cluster" -Cluster -PriorityValue8021Action 7 | Out-Null   
            New-NetQosTrafficClass "Cluster" -Priority 7 -BandwidthPercentage 1 -Algorithm ETS  | Out-Null
            #Set policy for SMB-Direct 
            Write-Host -ForegroundColor Yellow "+ Creating SMB NetQoSPolicy"
            New-NetQosPolicy "SMB" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3  | Out-Null
            Enable-NetQosFlowControl -priority 3  | Out-Null
            New-NetQosTrafficClass "SMB" -priority 3 -bandwidthpercentage 50 -algorithm ETS  | Out-Null

            foreach( $pNIC in $pNICs)
            {
                #Enabling QoS at NetAdapter Level
                Write-Host "+ Enabling NetQos on $($pNIC.NAme) adapter"
                Enable-NetAdapterQos -InterfaceAlias $pNIC.Name  | Out-Null
                #Block DCBX settings from the switch
                Write-Host "- Disabling NetQosDcbxSetting on $($pNIC.NAme) adapter"
                Set-NetQosDcbxSetting -InterfaceAlias $pNIC.Name -Willing $False -Force  | Out-Null
                #Disable flow control (Global Pause) on physical adapters
                Write-Host "+ Disabling IEEE 802.3 FlowControl on $($pNIC.NAme) adapter"
                Set-NetAdapterAdvancedProperty -Name $pNIC.Name -RegistryKeyword "*FlowControl" -RegistryValue 0  | Out-Null
            }

            #Set policy for the rest of the traffic 
            Write-Host -ForegroundColor Yellow "+ Creating Default traffic NetQoSPolicy"
            New-NetQosPolicy "DEFAULT" -Default -PriorityValue8021Action 0 | Out-Null
            Disable-NetQosFlowControl -priority 0,1,2,4,5,6,7  | Out-Null
        }
    } -ArgumentList $configdata[$node]  
}

#########
#####   Checking cluster nodes connectivity 
#########
################
Write-Host -ForegroundColor Yellow "########################################"
Write-Host -ForegroundColor Yellow "#    Checking cluster nodes connectivity"
Write-Host -ForegroundColor Yellow "########################################"

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
                    Write-Host "Checking networking connectivy from $env:computername to $node/$($vNIC.IpAddr)"
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