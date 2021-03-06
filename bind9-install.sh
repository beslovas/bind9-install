#!/bin/bash

#
# https://github.com/beslovas/bind9-install
#
# Copyright (c) 2022 Beslovas. Released under the MIT License.
#

ZONES_PATH="/var/lib/bind/zones"

[[ "$#" == 0 ]] && echo "Try './bind9-install.sh -h' for more information" && exit 1

usage()
{
    cat << USAGE >&2
Usage:
    ./bind9-install.sh [--zone <domain>]

    --zone <domain>      Define domain for default zone
    -h --help            Show this help dialog
USAGE
    exit 1
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --zone )
            shift
            DOMAIN=$1
            ;;
        -h | --help | * )
            usage
            exit 1
            ;;
    esac
    shift
done

[[ -z $DOMAIN ]] && echo -e "You must specify default zone.\n" && usage

DISTRO=""
get_distro()
{
    if [[ -e /etc/debian_version ]]; then
        VERSION=`cat /etc/debian_version | awk -F'.' '{print $1}'`
        [[ $VERSION -ge 10 ]] && DISTRO="debian" || DISTRO="debian-old"
    fi

    if [[ -e /etc/lsb-release ]]; then
        DISTRO="ubuntu"
    fi

    if [[ -e /etc/redhat-release ]]; then
        DISTRO="redhat"
    fi

    if [[ -e /etc/centos-release ]]; then
        DISTRO="centos"
    fi

    if [[ -e /etc/fedora-release ]]; then
        DISTRO="fedora"
    fi

    if [[ -e /etc/gentoo-release ]]; then
        DISTRO="gentoo"
    fi

    if [[ -e /etc/SuSE-release ]]; then
        DISTRO="suse"
    fi
}
get_distro

if [[ $DISTRO != @("ubuntu"|"debian"|"debian-old") ]]; then
    echo "Only ubuntu and debian distros are currently supported"
    exit 1
fi

setup_bind9()
{
    case "$DISTRO" in
        "debian-old" )
            apt -y update && apt -y install bind9 procps resolvconf
            sed -i 's/OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named
            systemctl enable --now named-resolvconf
            ;;
        "ubuntu"|"debian" )
            apt -y update && apt -y install bind9 bind9-dnsutils iproute2 resolvconf
            sed -i 's/OPTIONS=.*/OPTIONS="-4 -u bind"/' /etc/default/bind9
            systemctl enable --now bind9-resolvconf
            ;;
    esac

    [[ ! -d "$ZONES_PATH" ]] && mkdir $ZONES_PATH && chown bind:bind $ZONES_PATH

    cat << EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    recursion yes;
    listen-on port 53 { any; };
    forwarders { 8.8.8.8; 8.8.4.4; };
};
EOF
}
setup_bind9

restart_bind9()
{
    case "$DISTRO" in
        "debian-old" )
            service named restart
            ;;
        "ubuntu"|"debian" )
            service bind9 restart
            ;;
    esac
}
restart_bind9

IP=`ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p'`

OCTR21=`echo $IP | awk -F'.' '{print $2,$1}' OFS='.'`

KEY_SECRET=$(echo `echo $RANDOM | md5sum | head -c 24` | base64)


cat << EOF > $ZONES_PATH/$DOMAIN.key
key $DOMAIN. {
    algorithm hmac-md5;
    secret "$KEY_SECRET";
};
EOF

cat << EOF > /etc/bind/named.conf.local
include "$ZONES_PATH/$DOMAIN.key";

zone "$DOMAIN" {
    type master;
    update-policy {
        grant $DOMAIN zonesub any;
    };
    file "$ZONES_PATH/$DOMAIN";
};

zone "$OCTR21.in-addr.arpa" {
    type master;
    file "$ZONES_PATH/$DOMAIN.reverse";
};
EOF

cat << EOF > $ZONES_PATH/$DOMAIN
\$ORIGIN $DOMAIN.
\$TTL    604800
@       IN      SOA     ns.$DOMAIN. root.ns.$DOMAIN. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
; name servers - NS records
@     IN      NS      ns.$DOMAIN.
ns    IN      A       $IP
EOF

OCTR43=`echo $IP | awk -F'.' '{print $4, $3}'`

cat << EOF > $ZONES_PATH/$DOMAIN.reverse
\$TTL    604800
@       IN      SOA     $DOMAIN. root.$DOMAIN. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
; name servers
@       IN      NS      ns.$DOMAIN.

; PTR for DNS Server
$OCTR43  IN      PTR     ns.$DOMAIN.
EOF

chown -R bind:bind $ZONES_PATH

restart_bind9
