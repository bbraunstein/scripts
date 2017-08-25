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
  _ext=102
  _id=19
  INSERT INTO userman_users VALUES ("$_id", "freepbx", "NULL", "$_ext", "", "7ec68a7ebb7182d8ae89d3263ccdb3d849b3637a", "$_ext", "NULL", "fname", "lname", "disaplyname", "title", "company", "department", "email", "cell", "work", "home", "fax")
 
}
#}}}
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
