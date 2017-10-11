#!/bin/bash
# {{{ Header
#########################################################################################################
# Title       : check_ssl.sh                                                                            #
# Description : Checks the expiration date on SSL certs and calculates days remaining                   #
# Author      : Brian Braunstein <bbraunstein@modusagency.com>                                          #
# Created     : 02-21-2017                                                                              #
# Modified    : 02-23-2017                                                                              #
# Changes     :                                                                                         #
#               * Moved away from curl and added `openssl s_client` as our test case                    #
#               * Added test case to ensure a certificate is present, otherwise fail                    #
#                                                                                                       #
#########################################################################################################
#}}}

_curl=$(which curl)
_grep=$(which grep)
_awk=$(which awk)
_sed=$(which sed)
_date=$(which date)
_e=$(which echo)
_host=${1:?usage: $0 <target_host> <target port>}
_port=${2:-443}

edate=$(openssl s_client -connect ${_host}:${_port} 2>/dev/null </dev/zero| openssl x509 -noout -enddate | sed 's/notAfter=//')
# Put in place to fail if no SSL certificate is configured.
if [ -z "${edate}" ]
then
  ${_e} "No SSL cert found"
  exit 3
fi
cn=$(openssl s_client -connect ${_host}:${_port} 2>/dev/null </dev/zero| openssl x509 -noout -subject | sed 's/subject= //')
exp=$(${_date} --date="${edate}" +%s)
now=$(${_date} +%s)
result=$(((${exp} - ${now}) / 86400))

if [ "${result}" -le 7 ]
  then
    ${_e} "Critical: ${result} days remaining before cert expires! ${cn}"
    exit 2
  elif [ "${result}" -lt 60 ]
  then
    ${_e} "Warning: ${result} days remaining before cert expires - ${cn}"
    exit 1
  elif [ "${result}" -ge 60 ]
  then
    ${_e} "SSL Cert OK. Expiring on: ${edate}"
    exit 0
  else
    ${_e} "Invalid host or script ${0} error."
    exit 3
fi

