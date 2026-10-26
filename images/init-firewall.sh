#!/bin/bash
# Default-deny outbound firewall: only DNS, loopback, the host network and allowlisted
# destinations may be reached. Idempotent; run as root via sudo on every container start.
set -euo pipefail
IFS=$'\n\t'

DOMAINS_FILE=/etc/firewall-allowed-domains.txt

# Open policies while setting up (we need the network to fetch GitHub ranges and resolve names).
iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT
iptables -F; iptables -X
ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net

# GitHub publishes its address ranges (web, api, git).
gh_ranges=$(curl -fsS --max-time 15 https://api.github.com/meta)
echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null
for cidr in $(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -v ':'); do
    ipset add -exist allowed-domains "$cidr"
done

# Resolve every allowlisted hostname.
while read -r domain; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    ips=$(dig +short A "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [[ -z "$ips" ]]; then
        echo "WARNING: could not resolve $domain, skipping" >&2
        continue
    fi
    for ip in $ips; do ipset add -exist allowed-domains "$ip"; done
done < "$DOMAINS_FILE"

# Host network (VS Code server, port forwarding) = the default gateway's /24.
host_ip=$(ip route | awk '/default/ {print $3; exit}')
[[ -n "$host_ip" ]] || { echo "ERROR: no default gateway" >&2; exit 1; }
host_net=$(echo "$host_ip" | sed 's/\.[0-9]*$/.0\/24/')

iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A INPUT  -s "$host_net" -j ACCEPT
iptables -A OUTPUT -d "$host_net" -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT DROP

# Block IPv6 entirely so it cannot bypass the IPv4 allowlist.
ip6tables -P INPUT DROP; ip6tables -P FORWARD DROP; ip6tables -P OUTPUT DROP
ip6tables -A INPUT -i lo -j ACCEPT; ip6tables -A OUTPUT -o lo -j ACCEPT

# Verify: an arbitrary site must be blocked, GitHub must work.
if curl -fsS --max-time 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: firewall verification failed, example.com is reachable" >&2; exit 1
fi
curl -fsS --max-time 10 https://api.github.com/zen >/dev/null \
    || { echo "ERROR: firewall verification failed, api.github.com unreachable" >&2; exit 1; }
echo "Firewall active: outbound limited to allowlist."
