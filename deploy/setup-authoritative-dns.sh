#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

domain=rahisagallery.ir
ip=91.240.95.135
[[ $EUID -eq 0 ]]
command -v nsd-checkzone >/dev/null

parent=$(dig @193.189.123.2 "$domain" NS +norecurse +time=4 +tries=1 +noall +authority +additional)
for host in "ns1.$domain." "ns2.$domain."; do
    awk -v host="$host" -v ip="$ip" '$4=="NS" && $5==host {ns=1} $1==host && $4=="A" && $5==ip {glue=1} END {exit !(ns && glue)}' <<< "$parent"
done
ds=$(dig @193.189.123.2 "$domain" DS +norecurse +time=4 +tries=1 +noall +comments +answer)
grep -q 'status: NOERROR' <<< "$ds"
if grep -Eq '[[:space:]]DS[[:space:]]' <<< "$ds"; then
    printf '%s\n' 'A parent DS exists. Review the DNSSEC keys before enabling this zone.' >&2
    exit 1
fi

install -d -m 0755 /etc/nsd/nsd.conf.d /etc/nsd/zones
zone=/etc/nsd/zones/$domain.zone
config=/etc/nsd/nsd.conf.d/rahisa.conf
if [[ ! -e "$zone" ]]; then
    cat > "$zone" <<ZONE
\$ORIGIN $domain.
\$TTL 300
@ IN SOA ns1.$domain. hostmaster.$domain. (
    $(date -u +%Y%m%d01) 3600 600 1209600 300 )
@ IN NS ns1.$domain.
@ IN NS ns2.$domain.
@ IN A $ip
www IN CNAME $domain.
ns1 IN A $ip
ns2 IN A $ip
ZONE
fi
nsd-checkzone "$domain" "$zone"

if [[ ! -e "$config" ]]; then
    cat > "$config" <<CONFIG
server:
    ip-address: $ip
    hide-version: yes
zone:
    name: "$domain"
    zonefile: "$zone"
CONFIG
fi
if ! grep -Eq '^[[:space:]]*include:.*nsd\.conf\.d/\*\.conf' /etc/nsd/nsd.conf; then
    cp -p /etc/nsd/nsd.conf /etc/nsd/nsd.conf.rahisa-before
    printf '\ninclude: "/etc/nsd/nsd.conf.d/*.conf"\n' >> /etc/nsd/nsd.conf
fi
nsd-checkconf /etc/nsd/nsd.conf
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
    ufw allow 53/udp
    ufw allow 53/tcp
fi
systemctl enable nsd
systemctl restart nsd
for type in NS A AAAA; do
    dig @"$ip" "$domain" "$type" +norecurse +time=3 +tries=1 +noall +comments +answer
done
dig @"$ip" "www.$domain" A +norecurse +time=3 +tries=1 +noall +answer
dig @"$ip" "$domain" SOA +tcp +norecurse +time=3 +tries=1 +noall +answer
[[ $(dig @"$ip" "$domain" A +norecurse +time=3 +tries=1 +short) == "$ip" ]]
