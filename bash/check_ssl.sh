#!/bin/bash
# {{{ Header
#########################################################################################################
# Title       : check_ssl_expiry.sh                                                                     #
# Description : Checks the expiration date on SSL certs and calculates days remaining                   #
# Author      : Brian Braunstein <bbraunstein@modusagency.com>                                          #
# Created     : 02-21-2017                                                                              #
# Modified    : 02-21-2017                                                                              #
#########################################################################################################
#}}}

_curl=$(which curl)
_grep=$(which grep)
_awk=$(which awk)
_date=$(which date)
_e=$(which echo)
_host=${1:?usage: $0 <server>}

edate=$(${_curl} -sv ${_host} 2> >(${_grep} "expire date:" | ${_awk} '{print $4}'))
exp=$(${_date} --date="${edate}" +%s)
now=$(${_date} +%s)
result=$(((${exp} - ${now}) / 86400))

if [ "${result}" -lt 7 ]
  then
    ${_e} "Critical: ${result} days remaining before cert expires!"
    exit 3
  elif [ "${result}" -lt 60 ] && [ "${result}" -gt 7 ]
  then
    ${_e} "Warning: ${result} days remaining before cert expires."
    exit 2
  elif [ "${result}" -gt 60 ]
  then
    ${_e} "SSL Cert OK."
    exit 0
  else
    ${_e} "Script ${0} error"
    exit 1
fi

