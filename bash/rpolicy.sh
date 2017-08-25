#!/bin/bash
#########################################################################################################
# Description: Script will execute cleanup according to configuration and optionally optimize the table #
# Author: Brian Braunstein bbraunstein@modusagency.com                                                  #
# Date: October 6th, 2016                                                                               #
# Modified: October 14th, 2016                                                                          #
# rpolicy.sh > archive.log 2>&1 &                                                                 #
#########################################################################################################
# {{{ global variables
_pt_archiver=$(which pt-archiver)
_pt_online_schema_change=$(which pt-online-schema-change)
_host=${_host:=127.0.0.1}
_progress=${_progress:=1000}
_database=${_database:=leadrouter}
_datadir=$(grep datadir /etc/my.cnf | sed -e 's/datadir=//')
_logdir="/var/log/retention_policy"
_log_time=$(date +%Y%m%d-%H%M)
_log="${_logdir}/retention_policy-${_log_time}.log"
#}}}

# Verify logging directory exists, otherwise create it
if [ ! -d ${_logdir} ]
then
  mkdir ${_logdir}
fi


# {{{ functions
# {{{ echo()
function echo() {
  printf "$@\n" >> "${_log}"
  printf "$@\n"
}
#}}}
# {{{ usage()
function usage() {
  printf "Usage: table_cleanup [-t] table1[,table2,..] [OPTIONS]\n"
  printf "Options:\n"
  printf "  -D DATABASE             Database to connect to. Default is leadrouter.\n"
  printf "  -h                      Displays this help\n"
  printf "  -H HOST                 Host to run the retention policy against. Default is 127.0.0.1\n"
  printf "  -p PROGRESS             Print progress every N rows; Default is 1000\n"
  printf "  -v                      Verbose mode. Careful: verbose mode is extremely voluminous and can generate several megabytes of output\n"
  printf "  -t table1[,table2..]    Comma separated list of tables to act against (ex: email_out,lead_routing_log,email_in)\n"

  printf "Tables:\n"
  printf "  email_out              'date_created < DATE_SUB(DATE(NOW()), INTERVAL 3 MONTH)'\n"
  printf "  lead_routing_log       'date_created < DATE_SUB(DATE(NOW()), INTERVAL 12 MONTH)'\n"
  printf "  lead_iteration_user    'EXISTS(SELECT * FROM lead_iteration WHERE lead_iteration_id=lead_iteration.id AND date_added < DATE_SUB(DATE(NOW()), INTERVAL 12 MONTH))'\n"
  printf "  lead_iteration         'date_added < DATE_SUB(DATE(NOW()), INTERVAL 12 MONTH)'\n"
  printf "  api_log                'date_entered < DATE_SUB(DATE(NOW()), INTERVAL 3 MONTH) AND api_log.api_methods_id NOT IN (10,29)'\n"
  printf "  email_in               'date_created < DATE_SUB(DATE(NOW()), INTERVAL 3 MONTH) AND NOT EXISTS(SELECT * FROM lead WHERE email_in_id=email_in.id)'\n"
  exit 0 
}
#}}}
# {{{ purge()
function purge() {
  local _table=$1
  _query=${_query:-empty}
  
  case "$1" in
    email_out)
      _query='date_created < DATE_SUB(DATE(NOW()), INTERVAL 3 MONTH)'
      ;;
    lead_routing_log)
      _query='date_created < DATE_SUB(DATE(NOW()), INTERVAL 12 MONTH)'
      ;;
    lead_iteration_user)
      _query='EXISTS(SELECT * FROM lead_iteration WHERE lead_iteration_id=lead_iteration.id AND date_added < DATE_SUB(DATE(NOW()), INTERVAL 12 MONTH))'
      ;;
    lead_iteration)
      _query='date_added < DATE_SUB(DATE(NOW()), INTERVAL 12 MONTH)'
      ;;
    api_log)
      _query='date_entered < DATE_SUB(DATE(NOW()), INTERVAL 3 MONTH) AND api_log.api_methods_id NOT IN (10,29)'
      ;;
    email_in)
      _query='date_created < DATE_SUB(DATE(NOW()), INTERVAL 3 MONTH) AND NOT EXISTS(SELECT * FROM lead WHERE email_in_id=email_in.id)'
      ;;
    *)
      echo "Error! Unknown table entered: ${_table}"
      continue
    ;;
  esac


  echo "\"${_pt_archiver}\" --no-check-charset --primary-key-only --progress \"${_progress}\" --purge --source h=\"${_host}\",D=\"${_database}\",t=\"${_table}\" --where \"${_query}\"\n"
  "${_pt_archiver}" --no-check-charset --primary-key-only --progress "${_progress}" --purge --source h="${_host}",D="${_database}",t="${_table}" --where "${_query}" >> "${_log}" 2>&1
}
#}}}
# {{{ optimize()
function optimize() {
  local _table=$1
  
  ls -lh "${_datadir}"/leadrouter/"${_table}".* ## echo size of table BEFORE optimization
  
  if [ "${_table}" = "lead_iteration" ] || [ "${_table}" = "api_log" ] || [ "${_table}" = "email_in" ]
  then
  # echo the contents to the terminal 
    echo "\"${_pt_online_schema_change}\" --max-load Threads_running=100 --critical-load Threads_running=200 --set-vars innodb_lock_wait_timeout=50 --execute --nocheck-replication-filters --alter \"ENGINE=InnoDB\" D=\"${_database}\",t=\"${_table}\" --alter-foreign-keys-method auto\n"

    "${_pt_online_schema_change}" --max-load Threads_running=100 --critical-load Threads_running=200 --set-vars innodb_lock_wait_timeout=50 --execute --nocheck-replication-filters --alter "ENGINE=InnoDB" D="${_database}",t="${_table}" --alter-foreign-keys-method auto >> "${_log}" 2>&1
  
  else 
    # echo the contents to the terminal
   echo "\"${_pt_online_schema_change}\" --max-load Threads_running=100 --critical-load Threads_running=200 --set-vars innodb_lock_wait_timeout=50 --execute --nocheck-replication-filters --alter \"ENGINE=InnoDB\" D=\"${_database}\",t=\"${_table}\"\n"
  
    ${_pt_online_schema_change} --max-load Threads_running=100 --critical-load Threads_running=200 --set-vars innodb_lock_wait_timeout=50 --execute --nocheck-replication-filters --alter "ENGINE=InnoDB" D="${_database}",t="${_table}" >> "${_log}" 2>&1
  fi
  
  ls -lh "${_datadir}"/leadrouter/"${_table}".* ## echo size of table AFTER optimization
}
#}}
# {{{ main()
function main() {
  # verify percona-toolkit is installed, else install rpm
  rpm -q percona-toolkit >/dev/null 2>&1 || yum --nogpgcheck install -y http://percona.com/get/percona-toolkit.rpm
  
  touch "${_log}"
  # Split list of tables into parsable string
  if [ -n "$_tablelist" ]
    then
      for table in $_tablelist
        do
          echo "$(date +%F\ %r) \tStarting Execution Retention Policy for: leadrouter.$table\n"
          purge "$table"
          if [ "${_optimize}" ]
          then
            optimize "$table"
          fi          
          echo "$(date +%F\ %r) \tCompleted Execution Retention Policy for: leadrouter.$table\n"
      done
  fi
}
#}}}
#}}}
#}}}

# get runtime parameters
while getopts t:hH:p:dD:ov param
do
  case "${param}" in
    D) _database=${OPTARG};;        # database to run the retention policy against; default is leadrouter
    h) usage; exit 1;;              # Display help
    H) _host=${OPTARG};;            # change target host; default is LOCALHOST
    p) _progress=${OPTARG};;        # print progress every X rows; default is 1000 
    t) _tablelist=${OPTARG//,/ };;  # split comma-separated list of tables into parsable string
    o) _optimize=true;;             
    v) _PTDEBUG=true;;
    \?) usage
        exit 1
    ;;
    *) usage
       exit 1
    ;;
  esac
done
shift ${OPTIND-1}

if [ $_PTDEBUG ]
then
  echo "Executing retention policy in verbose mode...\n"
  export PTDEBUG=1
fi

main
