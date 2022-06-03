#!/bin/bash
#
# https://github.com/beslovas/bind9-install
#
# Copyright (c) 2022 Beslovas. Released under the MIT License.
#

if [[ "$#" == 0 ]]; then
    echo "Try './bind9-install.sh -h' for more information"
    exit 1
fi

usage()
{
    cat << USAGE >&2
Usage:
    ./bind9-install.sh [--zone <domain>]

    --zone <domain>  Define domain for default zone
    -h --help        Show this help dialog
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

DISTRO=""

get_distro() 
{
    if [[ -e /etc/debian_version ]]; then
        DISTRO="debian"
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

if [[ $DISTRO != "ubuntu" && $DISTRO != "debian" ]]; then
    echo "Only ubuntu and debian distros are currently supported"
    exit 1
fi

setup_bind9() 
{
    case "$DISTRO" in
        "debian" )
            apt -y update && apt -y install bind9 bind9utils procps
            sed -i 's/OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named
            ;;
        "ubuntu" )
            apt -y update && apt -y install bind9 bind9utils
            sed -i 's/OPTIONS=.*/OPTIONS="-4 -u bind"/' /etc/default/bind9
            ;;
    esac
}
setup_bind9

restart_bind9() 
{
    case "$DISTRO" in
        "debian" )
            service named restart
            ;;
        "ubuntu" )
            service bind9 restart
            ;;
    esac
}
restart_bind9

cat << EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    recursion yes;
    listen-on { localhost; };
    allow-transfer { none; };
    forwarders { 8.8.8.8; 8.8.4.4; };
};
EOF

IP=`ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p'`

OCTR21=`echo $IP | awk -F'.' '{print $2,$1}' OFS='.'`

cat << EOF > /etc/bind/named.conf.local
zone "$DOMAIN" {
    type master;
    file "/etc/bind/zones/$DOMAIN.forward";
};

zone "$OCTR21.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/$DOMAIN.reverse";
};
EOF

mkdir /etc/bind/zones

cat << EOF > /etc/bind/zones/$DOMAIN.forward
$TTL    604800
@       IN      SOA     ns.$DOMAIN. root.ns.$DOMAIN. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
; name servers - NS records
@     IN      NS      ns.$DOMAIN.

; name servers - A records
ns    IN      A       $IP

; A records
;host1.$DOMAIN.com.     IN      A      10.1.1.101
EOF

# insert A records for forward zone

OCTR43=`echo $IP | awk -F'.' '{print $4, $3}'`

cat << EOF > /etc/bind/zones/$DOMAIN.reverse
$TTL    604800
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

; PTR Records
;101.1 IN      PTR     host1.$DOMAIN.com.  ; 10.1.1.101
EOF

# insert PTR records for reverse zone

restart_bind9