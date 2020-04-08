@{
    ScriptVersion        = "2.0"

    S2DEnabled = $true

    LocalAdmin="labadmin"

    Nodes = 
    @(
        @{
            HypvNode = "EMEA-HP-01" 
            DCBEnabled= $true
            
            pNICS = 
            @(
                @{ Name = "pNIC1";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; jumboFrame=$true };
                @{ Name = "pNIC2";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16;  jumboFrame=$true };   
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
                                RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC1";  jumboFrame=$true;
                            };
                        @{   Name="SMB2"; Vlan=0; IpAddr="10.10.2.1"; CIDR=24; GW="10.10.2.254"; DNS=@();
                                RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC2";
                            };
                    ) 
                    };
            )

            AutoSyntheticAccelerationConfig=$true
        },
        #
        @{

            HypvNode = "EMEA-HP-02" 
            DCBEnabled= $true

            pNICS = 
            @(
                @{ Name = "pNIC1";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; jumboFrame=$true };
                @{ Name = "pNIC2";  RDMAEnabled=$true; RDMAMode="iWARP"; VmmqEnabled=$true; NumberOfReceiveQueues=16; jumboFrame=$true };   
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
                                RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC1"; jumboFrame=$true;
                            };
                        @{   Name="SMB2"; Vlan=0; IpAddr="10.10.2.2"; CIDR=24; GW="10.10.2.254"; DNS=@();
                                RDMAEnabled=$true; VmmqEnabled=$true; pNICAffinity="pNIC2"; jumboFrame=$true;
                            };
                    ) 
                    };

                )

            AutoSyntheticAccelerationConfig=$true
        }
    )
    
}