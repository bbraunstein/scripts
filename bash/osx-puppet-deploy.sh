#!/bin/bash

declare -a NODES
#NODES=(192.168.1.107 192.168.1.112 192.168.1.147 192.168.1.150 192.168.1.159 192.168.1.167 192.168.1.168 192.168.1.175 192.168.1.176 192.168.1.179 192.168.1.183 192.168.1.186 192.168.1.190 192.168.1.198 192.168.35.168 192.168.35.170 192.168.35.173 192.168.35.175 192.168.35.201 192.168.35.206 192.168.35.225 192.168.35.227 192.168.70.100 192.168.70.119 192.168.70.127 192.168.70.128)
NODES=(192.168.35.148)
touch fail.log

function puppet_deploy() {

  echo -e "\e[32mDeploying on host: $1...\e[0m"
  ssh -t root@"$1" "if [ -d /opt/puppetlabs/ ]; then exit 5;
                    else
                      ver=\$(sw_vers -productVersion | awk -F'.' '{print \$1\".\"\$2}');pupagent=puppet-agent-1.8.0-1;
                      curl https://downloads.puppetlabs.com/mac/\${ver}/PC1/x86_64/\${pupagent}.osx\${ver}.dmg > \${pupagent}.osx\${ver}.dmg || exit 10;
                      hdiutil attach -quiet -nobrowse \${pupagent}.osx\${ver}.dmg || exit 15;
                      installer -pkg /Volumes/\${pupagent}.osx\${ver}/\${pupagent}-installer.pkg -target / || exit 20;
                      hdiutil detach /Volumes/\${pupagent}.osx\${ver}/ || exit 25;
                      export PATH=/opt/puppetlabs/bin:\$PATH || exit 30;
                      puppet config set server puppet.modusagency.com || exit 35;
                      puppet resource service puppet ensure=stopped enable=false || exit 35;
                      rm -f \${pupagent}.osx\${ver}.dmg || exit 40;
                    fi"
  
  case "$?" in
    0)  echo -e "\e[1;32mCompleted deployment on: $1\e[0m" ;;
    5)  echo -e "\e[33mPuppet is already present. Skipping.\e[0m" ;;
    10) echo -e "\e[31mUnable to download image file.\\e[0m" ;;
    15) echo -e "\e[31mUnable to mount disk image.\e[0m";;
    20) echo -e "\e[31mUnable to install at target.\e[0m";;
    25) echo -e "\e[31mUnable to unmout disk image.\e[0m";;
    30) echo -e "\e[31mCan't set PATH for /opt/puppetlabs/bin:\$PATH\e[0m";;
    35) echo -e "\e[31mUnable to modify puppet settings. Check \$PATH is correctly set.\e[0m";;
    40) echo -e "\e[31mUnable to delete disk image file.\e[0m";;
  esac 
}

for i in "${NODES[@]}"; do
  ping -c 1 "${i}" > /dev/null 2>&1 #|| continue

  if [ $? -ne 0 ]; then
    echo -e "\e[1;31mHost: ${i} is unreachable!\e[0m"
    echo "${i}" >> fail.log
    continue
  fi

  puppet_deploy "${i}"

done


