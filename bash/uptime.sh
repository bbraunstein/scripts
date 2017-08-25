#!/bin/bash
# {{{ Header
#########################################################################################################
# Title       :                                                                                         #
# Description :                                                                                         #
# Author      : Brian Braunstein <bbraunstein@modusagency.com>                                          #
# Created     :                                                                                         #
# Modified    :                                                                                         #
#########################################################################################################
#}}}
# {{{ GLOBAL variables


#}}}


# {{{ functions

# {{{ main()
function main() {
  for i in {1..254}
  do
    ping -c 1 -W 1 192.168.100.$i &>/dev/null && ssh -o ConnectTimeout=1 root@192.168.100.$i 'echo "$(hostname): $(uptime)"'
  done
}
#}}}


# {{{ getopts
# parse for runtime parameters, if any
# value=${OPTARG} for variable assignment
while getopts 'h' param
do
  case "${param}" in
    h) usage; exit 1;;      # Display help

    *) usage; exit 1;;
  esac
done
shift ${OPTIND-1}
#}}}

main
