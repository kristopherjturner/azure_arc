@{

    # This is the PowerShell datafile used to provide configuration information for the HCIBox environment. Product keys and password are not encrypted and will be available on all hosts during installation.
    
    # Version 1.0.0

    # HCI host names
    StoreLocations                       = "Chicago", "New Orleans", "Seattle"                # The location names for the stores

    # VHDX Paths 
    L0VHDPath                          = "C:\Ag\VHD\L0.vhdx"              # This value controls the location of the GUI VHDX.              
    L1VHDPath                       = "C:\Ag\VHD\L1.vhdx"                 # This value controls the location of the Azure Stack HCI VHDX. 
    
    # SDN Lab Admin Password
    SDNAdminPassword                     = '%staging-password%'                  # Do not change - this value is replaced during Bootstrap with the password supplied in the ARM deployment

    # L1 VM Configuration
    HostVMPath                           = "V:\VMs"                              # This value controls the path where the Nested VMs will be stored the host.
    L1VMMemoryInGB                       = 16GB                                  # This value controls the amount of RAM for each AKS EE host VM
    L1VMNumVCPU                          = 4                                     # This value controls the number of vCPUs to assign to each AKS EE host VM
    InternalSwitch                       = "InternalSwitch"                      # Name of the internal switch that the L0 VM will use.

    # SDN Lab Domain
    SDNDomainFQDN                        = "jumpstart.local"                      # Limit name (not the .com) to 14 characters as the name will be used as the NetBIOS name. 
    DCName                               = "jumpstartdc"                          # Name of the domain controller virtual machine (limit to 14 characters)

    # NAT Configuration
    natHostSubnet                        = "192.168.128.0/24"
    natHostVMSwitchName                  = "InternalNAT"
    natConfigure                         = $true
    natSubnet                            = "192.168.46.0/24"                      # This value is the subnet is the NAT router will use to route to  AzSMGMT to access the Internet. It can be any /24 subnet and is only used for routing.
    natDNS                               = "%staging-natDNS%"                     # Do not change - can be configured by passing the optioanl natDNS parameter to the ARM deployment.

    # AKS variables
    AKSworkloadClusterName               = "hcibox-aks" # lowercase only
    AKSvnetname                          = "akshcivnet"
    AKSvSwitchName                       = "sdnSwitch"
    AKSNodeStartIP                       = "192.168.200.25"
    AKSNodeEndIP                         = "192.168.200.100"
    AKSVIPStartIP                        = "192.168.200.125"
    AKSVIPEndIP                          = "192.168.200.200"
    AKSIPPrefix                          = "192.168.200.0/24"
    AKSGWIP                              = "192.168.200.1"
    AKSDNSIP                             = "192.168.1.254"
    AKSCSV                               = "C:\ClusterStorage\S2D_vDISK1"
    AKSImagedir                          = "C:\ClusterStorage\S2D_vDISK1\aks\Images"
    AKSWorkingdir                        = "C:\ClusterStorage\S2D_vDISK1\aks\Workdir"
    AKSCloudConfigdir                    = "C:\ClusterStorage\S2D_vDISK1\aks\CloudConfig"
    AKSCloudSvcidr                       = "192.168.1.15/24"
    AKSVlanID                            = "200"
}