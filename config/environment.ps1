# =====================================================================
#  environment.ps1  --  SINGLE SOURCE OF TRUTH for the Autopilot
#  Hybrid Azure AD Join test lab.
#
#  Dot-source from any script:
#     . "$PSScriptRoot\..\config\environment.ps1"
#  then reference values via the $Lab hashtable, e.g. $Lab.Corp.HqDc1
#
#  All values were discovered on 2026-06-29. To reproduce the lab in a
#  different environment, edit the values here ONLY -- the phase scripts
#  read everything from this file.
# =====================================================================

$Global:Lab = [ordered]@{

  # --- Tower (Hyper-V host = the machine these scripts run on) ---
  Tower = [ordered]@{
    Hostname        = 'LAB-HOST'
    WgIface         = 'tower'                 # WireGuard tunnel interface name
    WgIp            = '10.200.200.2'
    WgListenPort    = 64599
    WgHubPeerPubKey = 'U0FNUExFLVZQUy1IVUItV0ctUFVCS0VZLW5vdC1yZWF='  # the VPS hub peer
  }

  # --- VPS (WireGuard hub: tower <-> VPS <-> laptop) ---
  Vps = [ordered]@{
    PublicIp = 'VPS_PUBLIC_IP'
    WgPort   = 51820
    WgSubnet = '10.200.200.0/24'
    SshName  = 'TBD'   # ssh-manager server name OR user@host (needed to edit hub AllowedIPs)
  }

  # --- Laptop (Site B; holds the corporate SSL VPN) ---
  Laptop = [ordered]@{
    Hostname     = 'VPN-LAPTOP'
    SshTarget    = 'labadmin@10.200.200.4'                 # reachable over the WG tunnel
    SshKey       = "$env:USERPROFILE\.ssh\id_ed25519"
    SshAlias     = 'siteb'                                  # ~/.ssh/config alias
    WgIface      = 'conection'
    WgIp         = '10.200.200.4'
    CorpVpnIface = 'Ethernet 3'                            # corporate SSL VPN Virtual Ethernet Adapter
    CorpVpnIp    = '10.0.30.135'
    CorpVpnGw    = '10.0.30.136'
  }

  # --- Corp (Contoso) ---
  Corp = [ordered]@{
    Domain         = 'corp.example.com'
    Tenant         = 'contoso.onmicrosoft.com'
    DnsServers     = @('10.0.10.1','10.0.10.2')    # = DC01 / DC02
    HqDc1Name      = 'DC01'
    HqDc1          = '10.0.10.1'
    HqDc2Name      = 'DC02'
    HqDc2          = '10.0.10.2'
    # /24s that host DCs the domain resolves to -- these get tunneled to the laptop:
    DcSubnets      = @('10.0.10.0/24','10.0.11.0/24','10.0.12.0/24','10.0.13.0/24','10.0.14.0/24')
    AutopilotGroup = 'CLIENT_Autopilot_HybridJoin'
    TargetOU       = 'OU=Computers,OU=HQ,OU=Contoso,DC=corp,DC=example,DC=com'
    LapsAccount    = 'client-admin'
  }

  # --- VM under test ---
  Vm = [ordered]@{
    Name       = 'CLIENT-AP-TEST01'
    Generation = 2                  # UEFI + Secure Boot + vTPM (required for Win11)
    MemoryGB   = 8                  # dynamic
    Cpu        = 4
    DiskGB     = 80
    SwitchName = 'AutopilotLab'     # dedicated Hyper-V *internal* switch
    LabSubnet  = '10.0.20.0/24' # isolated; verified non-overlapping with corp + tower
    LabGateway = '10.0.20.1'    # tower's IP on the internal switch (VM default gateway)
    LabPrefix  = 24
    VmDns      = @('10.0.10.1','10.0.10.2')   # corp DCs (resolve corp.example.com + forward internet)
    IsoPath    = 'C:\Users\<USER>\Downloads\Win11_lab.iso'   # Win11 25H2 x64 (Fido/official)
    VhdPath    = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\CLIENT-AP-TEST01.vhdx'
  }
}

# Convenience: write the data path the VM traffic takes, for logs/docs.
$Global:Lab.PathSummary = 'VM(10.0.20.0/24) -> tower NAT -> WG -> VPS(VPS_PUBLIC_IP) -> WG -> laptop(10.200.200.4) NAT -> corporate VPN(10.0.30.135) -> DCs(10.0.10.1/.2)'
