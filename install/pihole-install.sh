#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/pedro-pereira-dev/ProxmoxVE/raw/main/LICENSE
# Source: https://pi-hole.net/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Pi-hole"
mkdir -p /etc/pihole
touch /etc/pihole/pihole.toml
$STD bash <(curl -fsSL https://install.pi-hole.net) --unattended
sed -i -E \
  -e '/^\s*upstreams =/ s|=.*|= ["8.8.8.8", "8.8.4.4"]|' \
  -e '/^\s*domainNeeded =/ s|=.*|= true|' \
  -e '/^\s*expandHosts =/ s|=.*|= true|' \
  -e '/^\s*interface =/ s|=.*|= "eth0"|' \
  -e '/^\s*\[ntp.ipv4\]/,/^\s*\[/{s/^\s*active = true/  active = false/}' \
  -e '/^\s*\[ntp.ipv6\]/,/^\s*\[/{s/^\s*active = true/  active = false/}' \
  -e '/^\s*\[ntp.sync\]/,/^\s*\[/{s/^\s*active = true/  active = false/}' \
  -e '/^\s*pwhash =/ s|=.*|= ""|' \
  /etc/pihole/pihole.toml
echo -e "server=8.8.8.8\nserver=8.8.4.4" >/etc/dnsmasq.d/01-pihole.conf
systemctl restart pihole-FTL.service
msg_ok "Installed Pi-hole"

if whiptail \
  --title "Customize Pi-hole" \
  --yesno "Would you like to add Unbound?\n(https://wiki.omv-extras.org/)" \
  --defaultno \
  8 60; then

  if whiptail \
    --title "Customize Pi-hole" \
    --yesno "Unbound is configured as a recursive DNS server by default,\nwould you like to configure it as a forwarding DNS server instead? (using DNS-over-TLS (DoT))" \
    --defaultno \
    8 60; then
    cat <<EOF >>/etc/unbound/unbound.conf.d/pi-hole.conf
  tls-cert-bundle: "/etc/ssl/certs/ca-certificates.crt"
forward-zone:
  name: "."
  forward-tls-upstream: yes
  forward-first: no

  forward-addr: 8.8.8.8@853#dns.google
  forward-addr: 8.8.4.4@853#dns.google
  forward-addr: 2001:4860:4860::8888@853#dns.google
  forward-addr: 2001:4860:4860::8844@853#dns.google

  #forward-addr: 1.1.1.1@853#cloudflare-dns.com
  #forward-addr: 1.0.0.1@853#cloudflare-dns.com
  #forward-addr: 2606:4700:4700::1111@853#cloudflare-dns.com
  #forward-addr: 2606:4700:4700::1001@853#cloudflare-dns.com

  #forward-addr: 9.9.9.9@853#dns.quad9.net
  #forward-addr: 149.112.112.112@853#dns.quad9.net
  #forward-addr: 2620:fe::fe@853#dns.quad9.net
  #forward-addr: 2620:fe::9@853#dns.quad9.net
EOF

  else
    cat <<EOF >/etc/unbound/unbound.conf.d/pi-hole.conf
server:
  aggressive-nsec: yes
  cache-max-ttl: 14400
  cache-min-ttl: 300
  do-ip4: yes
  do-ip6: no
  do-tcp: yes
  do-udp: yes
  edns-buffer-size: 1232
  harden-algo-downgrade: no
  harden-dnssec-stripped: yes
  harden-glue: yes
  harden-referral-path: yes
  hide-identity: yes
  hide-version: yes
  infra-cache-slabs: 8
  interface: 127.0.0.1
  key-cache-slabs: 8
  msg-cache-size: 128m
  msg-cache-slabs: 8
  num-threads: 1
  port: 5335
  prefer-ip6: no
  prefetch-key: yes
  prefetch: yes
  private-address: 10.0.0.0/8
  private-address: 169.254.0.0/16
  private-address: 172.16.0.0/12
  private-address: 192.0.2.0/24
  private-address: 192.168.0.0/16
  private-address: 198.51.100.0/24
  private-address: 2001:db8::/32
  private-address: 203.0.113.0/24
  private-address: 255.255.255.255/32
  private-address: fd00::/8
  private-address: fe80::/10
  qname-minimisation: yes
  rrset-cache-size: 256m
  rrset-cache-slabs: 8
  rrset-roundrobin: yes
  serve-expired-ttl: 3600
  serve-expired: yes
  so-rcvbuf: 1m
  target-fetch-policy: "3 2 1 1 1"
  unwanted-reply-threshold: 10000000
  use-caps-for-id: no
  verbosity: 0
EOF
  fi

  msg_info "Installing Unbound"
  $STD apt install -y unbound
  echo "edns-packet-max=1232" >/etc/dnsmasq.d/99-edns.conf
  echo -e "server=127.0.0.1#5335\nserver=8.8.8.8\nserver=8.8.4.4" >/etc/dnsmasq.d/01-pihole.conf
  sed -i -E -e '/^\s*upstreams =/ s|=.*|= ["127.0.0.1#5335", "8.8.8.8", "8.8.4.4"]|' /etc/pihole/pihole.toml
  systemctl restart pihole-FTL.service
  msg_ok "Installed Unbound"
fi

if whiptail \
  --title "Customize Pi-hole" \
  --yesno "Would you like to sync this Pi-hole's configuration with another Pi-hole instance using nebula-sync? (https://github.com/lovelaze/nebula-sync)" \
  --defaultno \
  8 60; then
  address=$(whiptail --title "Setup nebula-sync" --inputbox "Pi-hole address:" 8 60 3>&1 1>&2 2>&3)
  password=$(whiptail --title "Setup nebula-sync" --inputbox "Pi-hole password:" 8 60 3>&1 1>&2 2>&3)
  msg_info "Installing nebula-sync"
  curl -Lfs "$(
    curl -s https://api.github.com/repos/lovelaze/nebula-sync/releases/latest |
      grep 'browser_download_url.*linux_amd64.tar.gz' | cut -d '"' -f 4
  )" | tar -xzC /usr/bin/
  chmod +x /usr/bin/nebula-sync
  cat <<EOF >/etc/nebula-sync.conf
PRIMARY=http://$address|$password
REPLICAS=http://127.0.0.1|

CRON=* * * * *
FULL_SYNC=true
RUN_GRAVITY=true
EOF
  cat <<EOF >/etc/systemd/system/nebula-sync.service
[Unit]
Description=Nebula Sync Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/nebula-sync run --env-file /etc/nebula-sync.conf
Restart=on-failure
RestartSec=1min

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nebula-sync.service
  msg_ok "Installed nebula-sync"
fi

motd_ssh
customize
cleanup_lxc
