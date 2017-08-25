#!/bin/sh
#
# Frequency analysis for apache logs:
#  * analyze the frequency of requests by hour [ speced ]
#  |-> count only page requests, e.g. no images, this should be handles via custom filter passed to the script
#  |-> count specific requests via the filter
#  * analyze the frequency of requests by IP, by-hour [ speced ]
#  * analyze the frequency of requests by URI action, by-hour [ speced ]
#  * analyze the frequency of requests by UserAgent, by-hour [ speced ]
#  * analyze the frequency of requests by HTTP status, by-hour [ speced ]
#
if [ $# -lt 2 ];
then
 echo "Error: missing parameter(s)!"
 echo "$0 <log> [-f <filter>|-i|-u]"
 exit
fi

LOG=${1}
shift 1
LOG_SIZE=$(wc -l ${LOG} | sed 's/ .*//')
if [ ${LOG_SIZE} -lt 100 ]; then
  echo "Error: apache log too small, <100 lines!"
  exit
fi
D_MARKER=$(sed ''$[${LOG_SIZE}/2]','$[${LOG_SIZE}/2]'p;d' ${LOG}|sed 's/kA.*//;s/.*\[//; s/\].*//;s/:.*//')
# Start/End timestamps
LOG_START=$(grep -m 1 ${D_MARKER} ${LOG} | sed 's/.*\[//; s/\].*//;s/ .*//')
LOG_END=$(tail -1 ${LOG} | sed 's/.*\[//; s/\].*//;s/ .*//')
T_START=$(echo ${LOG_START} | sed 's/.*\[//; s/\].*//;s/ .*//; s/[/:]/|/g; s/Jan/1/; s/Feb/2/; s/Mar/3/; s/Apr/4/;s/May/5/; s/Jun/6/; s/Jul/7/;s/Aug/8/; s/Sep/9/; s/Oct/10/; s/Nov/11/; s/Dec/12/;'| awk -F"|" '{print mktime($3" "$2" "$1" "$4" "$5" "$6)}')
T_END=$(echo ${LOG_END} | sed 's/.*\[//; s/\].*//;s/ .*//; s/[/:]/|/g; s/Jan/1/; s/Feb/2/; s/Mar/3/; s/Apr/4/;s/May/5/; s/Jun/6/; s/Jul/7/;s/Aug/8/; s/Sep/9/; s/Oct/10/; s/Nov/11/; s/Dec/12/;'| awk -F"|" '{print mktime($3" "$2" "$1" "$4" "$5" "$6)}')

# Exclude filters:
# * remove YMIA IPs
EXCLUDE_YMIA="24.136.116.9[0-4]"
# * exclude self
EXCLUDE_SELF="69.9.38.[45][16]"
# excludes expression
EXCLUDES="${EXCLUDE_YMIA}|${EXCLUDE_SELF}"

#awk '{print $1}' ${1} | grep -v -E ${EXCLUDES} | sort | uniq | sort -g > ${t_ip}

#sed 's/ - - //;s/\[\([0-9]\{2\}\)\//|\1/; s/Jan\//|1|/; s/Feb\//|2|/; s/Mar\//|3|/; s/Apr\//|4|/;s/May\//|5|/; s/Jun\//|6|/; s/Jul\//|7|/;s/Aug\//|8|/; s/Sep\//|9|/; s/Oct\//|10|/; s/Nov\//|11|/; s/Dec\//|12|/; s/:/|/g; s/ -[0-9]\{4\}\] "/|/; s/ HTTP.\{3,5\}" /|/;s/\([0-9]\+\) [0-9]* "-" "/\1|/;s/ +.*/|/' $1 | awk '{}'




function header(){
echo "File      : ${LOG}"
echo "Log start : ${LOG_START} : ${T_START}"
echo "Log end   : ${LOG_END} : ${T_END}"
echo "Filter    : ${FILTER}"
 }
 function fa_filtered(){
 echo "Frequency of requests by-the-hour [filter: ${msg}]"
 echo "Request Hour"
 #echo "grep ${FILTER} ${LOG} | sed 's/.*\[//; s/\].*//;s/ .*//' | grep ${LOG_START%%:*} | sed 's/.*[0-9]\{4\}://; s/:.*//' | sort | uniq -c"
 grep ${FILTER} ${LOG} | sed 's/.*\[//; s/\].*//;s/ .*//' | grep ${LOG_START%%:*} | sed 's/.*[0-9]\{4\}://; s/:.*//' | sort | uniq -c 
 }
 function fa_byIP(){
 echo "Top requester by-the-hour [IP]"
 echo "Request IP address     Hour"
 #echo "grep ${FILTER} ${LOG} | sed 's/.*\[//; s/\].*//;s/ .*//' | grep ${LOG_START%%:*} | sed 's/.*[0-9]\{4\}://; s/:.*//' | sort | uniq -c"
 for h in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23
 do
	 grep ${LOG_START%%:*}:${h} ${LOG}|sed 's/ .*//'|sort|uniq -c|sort -g|tail -1|sed 's/\(.\)$/\1\t'${h}'/'
 done
 }
 function fa_byUA(){
 echo "Top requester by-the-hour [user-agent]"
 echo "Request user-agent        Hour"
 #echo "grep ${FILTER} ${LOG} | sed 's/.*\[//; s/\].*//;s/ .*//' | grep ${LOG_START%%:*} | sed 's/.*[0-9]\{4\}://; s/:.*//' | sort | uniq -c"
 for h in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23
 do
	 #grep ${LOG_START%%:*}:${h} ${LOG}|sed 's/"$//; s/.*"//'|sort|uniq -c|sort -g|tail -1|sed 's/\(.\)$/\1\t'${h}'/'
	 grep ${LOG_START%%:*}:${h} ${LOG}|sed 's/"$//; s/.*"//;'|sort|uniq -c|sort -g|tail -1|sed  's/^\([ ]\+\)\([0-9]\+\).*([^ ]\+;/\1\2/; s/U;[ ]\+//; s/[;)].*//'|sed 's/\(.\)$/\1\t'${h}'/'
 done
 }

while getopts f:iu v
do
  case "${v}" in
  f) 				   
  FILTER="$OPTARG"
  if [ -z "${FILTER}" ]; then
   	msg="(unfiltered)"
    FILTER="."
  else
    msg="${FILTER}"
  fi
  header
  echo
  fa_filtered
  ;;
  i)
  header
  echo
  fa_byIP
  ;;
  u)
  header
  echo
  fa_byUA
  ;;
    [?]) 
    echo "$0 <log> [-f <filter>|-i|-u]"
    exit 1
  ;;
esac 
done

