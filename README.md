# autopilot-lab

autopilot-lab is a small lab I use to test Windows Autopilot Hybrid Azure AD Join against a real on-prem domain, without shipping a machine to the site or giving the test machine any company credentials of its own. It is a method more than a product, and every name and address in it is a fake placeholder.

The interesting part is the networking. For Hybrid Join to work, the machine has to reach a domain controller during setup, but the only company access I had was a VPN on a laptop in a different place, and both machines sit behind NAT with no public address. So the setup is a double hop. A throwaway Hyper-V VM on my tower reaches the domain controllers over a WireGuard tunnel that runs tower to a small public VPS to the laptop, and the laptop is the one actually on the company VPN. Only the DC subnets go through the tunnel. Everything else the VM does, all the Microsoft cloud setup traffic, goes straight out to the internet, so it stays fast.

The scripts are split by machine and driven from one config file. There is one to build the VM, one to grab its hardware hash offline, one to import it into Autopilot over the Graph API, and one to check the enrolment afterwards.

## where it is at

The tunnel and the split routing work, and so do the VM build and the offline hardware hash capture. The full interactive Hybrid Join was paused before it finished in the reference run, because the remote laptop had to go offline, so treat the verify script as the check for that step rather than proof it passed. It is a single operator test lab, not production tooling.
