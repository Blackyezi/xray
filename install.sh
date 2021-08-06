#!/bin/bash

rm -rf $0

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}error：${plain} Must be run as root user\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}The system version is not detected, please contact the script author${plain}\n" && exit 1
fi

arc=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
   arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
   arch="arm64-v8a"
else
   arch="64"
   echo -e "${red}Failed to detect the architecture, use the default architecture: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "This software does not support 32-bit system (x86), please use 64-bit system (x86_64), if the detection is wrong, please contact the author"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or higher${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or higher${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
}

install_XrayR() {
    if [[ -e /usr/local/XrayR/ ]]; then
        rm /usr/local/XrayR/ -rf
    fi

    mkdir /usr/local/XrayR/ -p
	cd /usr/local/XrayR/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/amfiyong/XrayR/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to detect the XrayR version, it may be beyond the Github API limit, please try again later, or manually specify the XrayR version to install${plain}"
            exit 1
        fi
        echo -e "The latest version of XrayR detected：${last_version}，Start installing"
        wget -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip https://github.com/amfiyong/XrayR/releases/download/${last_version}/XrayR-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download XrayR failed，Please make sure your server can download Github files${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/amfiyong/XrayR/releases/download/${last_version}/XrayR-linux-${arch64}.zip"
        echo -e "Start to install XrayR v$1"
        wget -N --no-check-certificate -O /usr/local/XrayR/XrayR-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download XrayR v$1 failed，Please make sure this version exists${plain}"
            exit 1
        fi
    fi

    unzip XrayR-linux.zip
    rm XrayR-linux.zip -f
    chmod +x XrayR
    mkdir /etc/XrayR/ -p
    rm /etc/systemd/system/XrayR.service -f
    file="https://github.com/amfiyong/xray/raw/master/XrayR.service"
    wget -N --no-check-certificate -O /etc/systemd/system/XrayR.service ${file}
    #cp -f XrayR.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop XrayR
    systemctl enable XrayR
    echo -e "${green}XrayR ${last_version}${plain} The installation is complete, and the boot has been set to start automatically"
    cp geoip.dat /etc/XrayR/
    cp geosite.dat /etc/XrayR/ 

    if [[ ! -f /etc/XrayR/config.yml ]]; then
        cp config.yml /etc/XrayR/
        echo -e ""
        echo -e "For a new installation, please refer to the tutorial first: https://github.com/amfiyong/XrayR, configure the necessary content"
    else
        systemctl start XrayR
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR Restart Successful${plain}"
        else
            echo -e "${red}XrayR may fail to start. Please use XrayR log to check the log information later. If it fails to start, the configuration format may have been changed. Please go to wiki to check：https://github.com/amfiyong/XrayR/wiki${plain}"
        fi
    fi

    if [[ ! -f /etc/XrayR/dns.json ]]; then
        cp dns.json /etc/XrayR/
    fi
    
    curl -o /usr/bin/XrayR -Ls https://raw.githubusercontent.com/amfiyong/xray/master/XrayR.sh
    chmod +x /usr/bin/XrayR
    ln -s /usr/bin/XrayR /usr/bin/xrayr 
    chmod +x /usr/bin/xrayr
    #curl -o /usr/bin/XrayR-tool -Ls https://raw.githubusercontent.com/amfiyong/XrayR/master/XrayR-tool
    #chmod +x /usr/bin/XrayR-tool
    echo -e ""
    echo "XrayR Script usage: "
    echo "------------------------------------------"
    echo "XrayR              - Show menu"
    echo "XrayR start        - Start     XrayR"
    echo "XrayR stop         - Stop      XrayR"
    echo "XrayR restart      - Restart   XrayR"
    echo "XrayR status       - View      XrayR Status"
    echo "XrayR enable       - Setting   XrayR self-start"
    echo "XrayR disable      - Disable   XrayR self-start"
    echo "XrayR log          - View      XrayR log"
    echo "XrayR update       - Update    XrayR"
    echo "XrayR update x.x.x - UPdate    XrayR specify version"
    echo "XrayR install      - Install   XrayR"
    echo "XrayR uninstall    - Uninstall XrayR"
    echo "XrayR version      - Check     XrayR version"
    echo "------------------------------------------"
}

echo -e "${green}Start to install${plain}"
install_base
install_acme
install_XrayR $1
