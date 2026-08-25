# FortiGate Configuration — Key Excerpts (Sanitized)

**Sourcing note:** the sections below are drawn directly from a real `show full-configuration` pull (35,382 lines) of the live FortiGate, condensed to the fields that matter for understanding the design — the full output includes thousands of lines of default-value fields for every subsystem (switch-controller, wireless-controller, IPS, BGP/OSPF/ISIS that aren't in use, etc.) that add no value here. Every value shown below is verified against that real pull; all real IPs, passwords, hashes, and tokens are replaced by clearly-marked placeholders. The full unredacted file is not included in this repo — regenerate it yourself with `scripts/backup-fortigate.sh` if you want the literal complete export.

---

## VLAN interfaces

```
config system interface
    edit "VLAN10_Trusted"
        set vdom "root"
        set ip <TRUSTED_GATEWAY_IP> 255.255.255.0
        set allowaccess ping https ssh snmp
        set type vlan
        set device-identification enable
        set role lan
        set snmp-index 17
        set interface "internal1"
        set vlanid 10
    next
    edit "VLAN20_Guest"
        set vdom "root"
        set ip <GUEST_GATEWAY_IP> 255.255.255.0
        set allowaccess ping
        set type vlan
        set role lan
        set snmp-index 18
        set interface "internal1"
        set vlanid 20
    next
    edit "VLAN30_Servers"
        set vdom "root"
        set ip <SERVERS_GATEWAY_IP> 255.255.255.0
        set allowaccess ping https ssh snmp
        set type vlan
        set role lan
        set snmp-index 19
        set interface "internal1"
        set vlanid 30
    next
    edit "VLAN40_DMZ"
        set vdom "root"
        set ip <DMZ_GATEWAY_IP> 255.255.255.0
        set allowaccess ping
        set type vlan
        set role dmz
        set snmp-index 20
        set interface "internal1"
        set vlanid 40
    next
    edit "internal2"
        set vdom "root"
        set ip <BRANCH_TRANSIT_IP> 255.255.255.252
        set allowaccess ping
        set role lan
        set snmp-index 5
    next
end
```

## Firewall policies (segmentation core)

```
config firewall policy
    edit 1
        set name "Trusted_to_Internet"
        set srcintf "VLAN10_Trusted"
        set dstintf "wan1"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set nat enable
    next
    edit 2
        set name "Guest_to_Internet"
        set srcintf "VLAN20_Guest"
        set dstintf "wan1"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set dnsfilter-profile "Guest_DMZ_Filter"
        set nat enable
    next
    edit 3
        set name "Guest_to_Trusted_DENY"
        set srcintf "VLAN20_Guest"
        set dstintf "VLAN10_Trusted"
        set action deny
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set logtraffic all
    next
    edit 4
        set name "Guest_to_Servers_DENY"
        set srcintf "VLAN20_Guest"
        set dstintf "VLAN30_Servers"
        set action deny
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set logtraffic all
    next
    edit 5
        set name "Trusted_to_Servers"
        set srcintf "VLAN10_Trusted"
        set dstintf "VLAN30_Servers"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set nat enable
    next
    edit 6
        set name "Servers_to_Internet"
        set srcintf "VLAN30_Servers"
        set dstintf "wan1"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set nat enable
    next
    edit 7
        set name "DMZ_to_Internet"
        set srcintf "VLAN40_DMZ"
        set dstintf "wan1"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set dnsfilter-profile "Guest_DMZ_Filter"
        set nat enable
    next
    edit 8
        set name "SSLVPN_to_Trusted"
        set srcintf "ssl.root"
        set dstintf "VLAN10_Trusted"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set groups "<VPN_USER_GROUP>"
        set schedule "always"
        set service "ALL"
        set nat disable
    next
    edit 9
        set name "Branch_to_Internet"
        set srcintf "internal2"
        set dstintf "wan1"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set nat enable
    next
    edit 10
        set name "Branch_to_HQ_DENY"
        set srcintf "internal2"
        set dstintf "internal1"
        set action deny
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set logtraffic all
    next
    edit 11
        set name "Servers_to_Trusted_Monitoring"
        set srcintf "VLAN30_Servers"
        set dstintf "VLAN10_Trusted"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set nat disable
    next
    edit 12
        set name "Servers_to_Branch_Monitoring"
        set srcintf "VLAN30_Servers"
        set dstintf "internal2"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
        set nat disable
    next
end
```

**Note:** all 12 policy IDs and names above are verified against the real, live FortiGate configuration — this is the actual, current policy set, not a reconstruction.

## SSL-VPN settings

```
config vpn ssl settings
    set status enable
    set ssl-max-proto-ver tls1-3
    set ssl-min-proto-ver tls1-2
    set banned-cipher SHA1
    set ciphersuite TLS-AES-128-GCM-SHA256 TLS-AES-256-GCM-SHA384 TLS-CHACHA20-POLY1305-SHA256
    set servercert "Fortinet_Factory"
    set tunnel-ip-pools "SSLVPN_TUNNEL_ADDR1"
    set dns-server1 <TRUSTED_GATEWAY_IP>
    set port 10443
    set source-interface "wan1"
    set source-address "all"
    set default-portal "full-access"
end
```

**Note:** the `banned-cipher` field above shows only `SHA1` — the correct end state after fixing the self-conflict documented in [`../../docs/TROUBLESHOOTING-LOG.md`](../../docs/TROUBLESHOOTING-LOG.md) Part 11. The original misconfiguration (`SHA1 SHA256 SHA384`, which conflicted with the required cipher suite) is preserved there as the bug narrative — this file reflects the fixed, working config.

## RIP routing

```
config router rip
    config network
        edit 1
            set prefix <BRANCH_TRANSIT_SUBNET> 255.255.255.252
        next
        edit 2
            set prefix <TRUSTED_SUBNET> 255.255.255.0
        next
        edit 3
            set prefix <GUEST_SUBNET> 255.255.255.0
        next
        edit 4
            set prefix <SERVERS_SUBNET> 255.255.255.0
        next
        edit 5
            set prefix <DMZ_SUBNET> 255.255.255.0
        next
    end
end
```

## DNS filter (Guest/DMZ)

```
config dnsfilter profile
    edit "Guest_DMZ_Filter"
        set comment "DNS filtering for Guest and DMZ outbound traffic"
        config ftgd-dns
            config filters
                edit 1
                    set category 26  # Malicious Websites
                next
                edit 2
                    set category 61  # Phishing
                next
                edit 3
                    set category 88  # Dynamic DNS
                next
            end
        end
        config domain-filter
            config entries
                edit 1
                    set domain "*.duckdns.org"
                    set type wildcard
                    set action allow
                next
                edit 2
                    set domain "*.cloudflare.com"
                    set type wildcard
                    set action allow
                next
                edit 3
                    set domain "*.argotunnel.com"
                    set type wildcard
                    set action allow
                next
                edit 4
                    set domain "*.debian.org"
                    set type wildcard
                    set action allow
                next
            end
        end
    next
end
```

**Note:** the `*.cloudflare.com`, `*.argotunnel.com`, and `*.debian.org` allow entries were added after the DNS filter incident documented in the troubleshooting log's Deployment section — these domains were initially caught by the broader category blocks above before being explicitly allowed.
