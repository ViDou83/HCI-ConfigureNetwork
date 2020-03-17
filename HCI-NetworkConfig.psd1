@{
    ScriptVersion        = "2.0"

    S2DEnabled = $true

    LocalAdmin="labadmin"

    Nodes = @("Redstone-HP-01","Redstone-HP-02")

    "Redstone-HP-01" = @{
        
        DCBEnabled= $true

        pNICS = 
        @(
            @{ Name = "pNIC1";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; };
            @{ Name = "pNIC2";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; };   
        )

        vSwitches = 
        @( 
                @{ 
                Name = "S2DSwitch"; 
                SetEnabled = $true
                MgmtOS = $false
                pNICs =  @( 
                                @{ name = "pNIC1" };
                                @{ name = "pNIC2" };
                )

                HostvNICs = 
                @(
                    @{   Name="SMB1"; Vlan=0; IpAddr="10.10.1.1"; CIDR=24; GW="10.10.1.254"; DNS=@();
                            RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC1";
                        };
                    @{   Name="SMB2"; Vlan=0; IpAddr="10.10.2.1"; CIDR=24; GW="10.10.2.254"; DNS=@();
                            RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC2";
                        };
                ) 
                };
        )

        AutoSyntheticAccelerationConfig=$true
   }

   "Redstone-HP-02" = @{

        DCBEnabled= $true

        pNICS = 
        @(
            @{ Name = "pNIC1";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; };
            @{ Name = "pNIC2";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; };   
        )

        vSwitches = 
        @( 
                @{ 
                Name = "SDN"; 
                SetEnabled = $true
                MgmtOS = $false
                pNICs =  @( 
                                @{ name = "pNIC1" };
                                @{ name = "pNIC2" };
                )

                HostvNICs = 
                @(
                    @{   Name="SMB1"; Vlan=0; IpAddr="10.10.1.2"; CIDR=24; GW="10.10.1.254"; DNS=@();
                            RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC1";
                        };
                    @{   Name="SMB2"; Vlan=0; IpAddr="10.10.2.2"; CIDR=24; GW="10.10.2.254"; DNS=@();
                            RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC2";
                        };
                ) 
                };

            )

        AutoSyntheticAccelerationConfig=$true
    }
    
}