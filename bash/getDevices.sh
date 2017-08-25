#!/bin/bash

NODE=(192.168.1.201 192.168.1.237 192.168.1.207 192.168.1.239 192.168.1.205 192.168.1.188 192.168.1.202 192.168.1.240 192.168.1.209 192.168.1.238 192.168.1.204 192.168.1.173 192.168.1.206 192.168.1.236 192.168.1.203 192.168.1.210 192.168.1.233 192.168.1.219 192.168.1.215 192.168.1.217 192.168.1.232 192.168.1.211 192.168.1.213)

#touch devices.csv

for i in "${NODE[@]}"; do
  MAC=$(curl -s -m 3 ${i} | grep -E "MAC" | awk -F '>' '{print $5}' | sed 's/<\/font//;s/-//')
    BRAND=$(curl -s -m 3 ${i} | grep -E "Product Name" | awk -F '>' '{print $5}' | sed 's/<\/font//;s/-//')
    FILE=$(echo ${MAC} | tr [A-Z] [a-z] | sed 's/\(.*\)/spa\1.xml/')
    EXT=$(grep User_ID ~/configs/"${FILE}" | sed -e 's/\(<User_ID_1_ ua=\"na\">\)\(.*\)\(<\/User_ID_1_>\)/\2/;s/^[ \t]*//')

    echo "$MAC,Cisco/Linksys,$BRAND,$EXT,1" #>> devices.csv
done
