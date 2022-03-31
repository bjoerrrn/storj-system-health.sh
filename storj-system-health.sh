#!/bin/bash
#
# v1.6.9
#
# storj-system-health.sh - storagenode health checks and notifications to discord / by email
# by dusselmann, https://github.com/dusselmann/storj-system-health.sh
# This script is licensed under GNU GPL version 3.0 or above
# 
# > requires discord.sh from https://github.com/ChaoticWeg/discord.sh
# > uses parts of storj_success_rate from https://github.com/ReneSmeekes/storj_success_rate
# 
# -------------------------------------------------------------------------

# let the script run in low performance to not block the system
renice 19 $$ 

# =============================================================================
# CHECK AND HANDLE PARAMETERS
# ------------------------------------

# default values

config_file="./storj-system-health.credo"      # config file path
settings_file=".storj-system-health"           # settings file path

DEB=0                                          # debug mode flag
VERBOSE=false                                  # verbose mode flag
LOGMIN_OVERRIDE=0                              # LOGMIN override flag 
UNAMEOUT="$(uname -s)"                         # get OS name (darwin for mac os, linux etc.)
TODAY=$(date +%Y-%m-%d)                        # todays date in format yyyy-mm-dd

satellite_notification=false                   # send satellite notification flag
settings_satellite_key="satping"               # settings satellite ping key
settings_satellite_timestamp=$(date +%s)       # settings satellite ping value of now

# help text

readonly help_text="Usage: $0 [OPTIONS]

Example: $0 -dv

General options:
  -h            Display this help and exit
  -c <path>     Use individual file path for properties
  -s <path>     Use individual fiel path for settings
  -d            Debug mode: send discord push if health check ok
  -m            Debug mode: discord push + test settings by sending test mail
  -p <path>     Provide a path to support crontab on MacOS
  -l <int>.     Override LOGMIN specified in settings, format: minutes as integer
  -v            Verbose option to enable console output while execution"

# parameter handling

while getopts ":hc:s:dmp:l:v" flag
do
    case "${flag}" in
        c) config_file=${OPTARG};;
        s) settings_file=${OPTARG};;
        d) DEB=1;;
        m) DEB=2;;
        p) PATH=${OPTARG};;
        l) LOGMIN_OVERRIDE=${OPTARG};;
        v) VERBOSE=true;;
        h | *) echo "$help_text" && exit 0;;
    esac
done
shift $((OPTIND-1))

# get current dir of this script
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

[[ "$VERBOSE" == "true" ]] && echo "==="
[[ "$VERBOSE" == "true" ]] && echo -e " *** timestamp [$(date +'%d.%m.%Y %H:%M')]"
[[ "$VERBOSE" == "true" ]] && [[ $DEB -eq 1 ]] && echo -e " *** discord debug mode on"
[[ "$VERBOSE" == "true" ]] && [[ $DEB -eq 2 ]] && echo -e " *** mail debug mode on"


# =============================================================================
# DEFINE FUNCTIONS
# ------------------------------------

function updateSettingsSatellitePing() {
    sed -i -e "s/$settings_satellite_key=$satping/$settings_satellite_key=$settings_satellite_timestamp/g" "$settings_file"
    [[ "$VERBOSE" == "true" ]] && echo " *** settings: latest satellite ping saved [$(date +'%d.%m.%Y %H:%M')]."
}

function restoreSettings() {
    [[ "$VERBOSE" == "true" ]] && echo " *** settings: restoring file:"
    echo "$settings_satellite_key=$settings_satellite_timestamp" > $settings_file
    [[ "$VERBOSE" == "true" ]] && echo " *** settings: latest satellite ping saved [$(date +'%d.%m.%Y %H:%M')]."
    # .. other values to be appended with >> instead of > !
}

# =============================================================================
# DEFINE VARIABLES AND CONSTANTS
# ------------------------------------

if [[ "$DISCORDON" == "true" ]]
then 
    # check, if discord.sh script exists and is executable
    if [ ! -x "$DIR/discord.sh" ]
    then
        echo "fatal: discord.sh does not exist or is not executable:$DIR/discord.sh"
        exit 2
    fi
fi


# check, if config file exists and is readable
if [ ! -r "$config_file" ]
then
    echo "fatal: config file $config_file not found / readable."
    exit 2
else 
    # loads config data into variables 
    { while IFS== read var values ; do IFS=, read -a $var <<< "$values";  done < "$config_file"; } 2>/dev/null


    [[ -z "$DISCORDON" ]] && echo "fatal: DISCORDON not specified in .credo" && exit 2
    if [[ "$DISCORDON" == "true" ]]
    then 
        [[ -z "$DISCORDURL" ]] && echo "fatal: DISCORDURL not specified in .credo" && exit 2
    fi
    
    
    [[ -z "$MAILON" ]] && echo "fatal: MAILON not specified in .credo" && exit 2
    if [[ "$MAILON" == "true" ]]
    then 
        [[ -z "$MAILFROM" ]] && echo "fatal: MAILFROM not specified in .credo" && exit 2
        [[ -z "$MAILTO" ]] && echo "fatal: MAILTO not specified in .credo" && exit 2
        [[ -z "$MAILSERVER" ]] && echo "fatal: MAILSERVER not specified in .credo" && exit 2
        [[ -z "$MAILUSER" ]] && echo "fatal: MAILUSER not specified in .credo" && exit 2
        [[ -z "$MAILPASS" ]] && echo "fatal: MAILPASS not specified in .credo" && exit 2
    fi
    
    [[ -z "$NODES" ]] && echo "failure: NODES not specified in .credo" && exit 2
    [[ -z "$MOUNTPOINTS" ]] && echo "failure: MOUNTPOINTS not specified in .credo" && exit 2
    [[ -z "$NODEURLS" ]] && echo "failure: NODEURLS not specified in .credo" && exit 2


    if [[ -z "$LOGMIN" ]]; then
        echo "LOGMIN=60" >> $config_file
        echo "warning: LOGMIN was not specified in .credo, but was added now."
        echo "         You need to restart the script to make it work."
        echo "         Script has been stopped."
        exit 2
    fi

    if [[ -z "$LOGMAX" ]]; then
        echo "LOGMAX=1440" >> $config_file
        echo "warning: LOGMAX was not specified in .credo, but was added now."
        echo "         You need to restart the script to make it work."
        echo "         Script has been stopped."
        exit 2
    fi


    if [[ -z "$SATPINGFREQ" ]]; then
        echo "SATPINGFREQ=10800" >> $config_file
        echo "warning: SATPINGFREQ was not specified in .credo, but was added now."
        echo "         You need to restart the script to make it work."
        echo "         Script has been stopped."
        exit 2
    fi
    
    
    if [[ -z "$NODELOGPATHS" ]]; then
        tmp_commas=
        for (( i=0; i<${#NODES[@]}; i++ ))
        do
            tmp_commas="$(echo $tmp_commas/)"
            if [[ $i -lt ${#NODES[@]}-1 ]]; then
                tmp_commas="$(echo $tmp_commas,)"
            fi
        done
        echo "NODELOGPATHS=$tmp_commas" >> $config_file
        echo "warning: NODELOGPATHS was not specified in .credo, but was added now."
        echo "         --> If you've redirected your logs, you need to modify .credo."
        echo "         You need to restart the script to make it work."
        echo "         Script has been stopped."
        exit 2
    fi
    
    # quality checks
    [[ ${#MOUNTPOINTS[@]} -ne ${#NODES[@]} ]] && echo "failure: number of NODES and MOUNTPOINTS do not match in .credo" && exit 2
    [[ ${#NODEURLS[@]} -ne ${#NODES[@]} ]] && echo "failure: number of NODES and NODEURLS do not match in .credo" && exit 2
    [[ ${#NODELOGPATHS[@]} -ne ${#NODES[@]} ]] && echo "failure: number of NODES and NODELOGPATHS do not match in .credo" && exit 2

    [[ "$VERBOSE" == "true" ]] && echo " *** config file loaded"
fi

[[ "$VERBOSE" == "true" ]] && [[ $LOGMIN_OVERRIDE -gt 0 ]] && echo " *** settings: logs from the last $LOGMIN_OVERRIDE minutes will be selected"

# loads settings file into variables
if [ ! -r "$settings_file" ]; then
    # if not existing or readable, create a new file
    restoreSettings
else
    # if existing and readable, read its content
    while IFS== read var values
    do
        IFS=, read -a $var <<< "$values"
    done < "$settings_file"
    if [[ -z "$satping" ]]
    then
        [[ "$VERBOSE" == "true" ]] && echo "warning: settings: satping not found."
        satellite_notification=true  # do perform the satellite notification
        updateSettingsSatellitePing  # set current date
    fi
    # compare, if dates are equal or not
    # if unequal, perform satellite notification, else not
    difference=$(($settings_satellite_timestamp-$satping))
    #echo "current: $settings_satellite_timestamp"
    #echo "satping: $satping"
    #echo "difference: $difference"
    if [[ $difference -gt $SATPINGFREQ ]]
    then
        satellite_notification=true  # do perform the satellite notification
        updateSettingsSatellitePing  # replace old date with current date
    fi
    #if [[ $DEB -eq 1 ]]
    #then
    #    satellite_notification=true  # do perform the satellite notification anyway when flag -d
    #fi
    [[ "$VERBOSE" == "true" ]] && echo " *** settings: satellite pings will be sent: $satellite_notification"
fi 


# =============================================================================
# CHECK DEPENDENCIES AND LIBRARIES
# ------------------------------------

# check for jq
jq --version >/dev/null 2>&1
readonly jq_ok=$?
[[ "$jq_ok" -eq 127 ]] && echo "fatal: jq not installed" && exit 2
[[ "$jq_ok" -ne 0 ]] && echo "fatal: unknown error in jq" && exit 2
# jq exists and runs ok

# verify jq version minimum 1.6 
jqversion="$(echo \"$(jq --version)\" | grep -o '[0-9]*[\.][0-9]*')" 
[[ $(echo $jqversion '<' 1.6 | bc -l) -eq 1 ]] && echo "fatal: jq version 1.6 required (installed: $jqversion)" && exit 2

# check for curl
curl --version >/dev/null 2>&1
readonly curl_ok=$?
[[ "$curl_ok" -eq 127 ]] && echo "fatal: curl not installed" && exit 2
# curl exists and runs ok

# check for swaks
if [[ "$MAILON" == "true" ]]
then 
    swaks --version >/dev/null 2>&1
    readonly swaks_ok=$?
    [[ "$swaks_ok" -eq 127 ]] && echo "fatal: swaks not installed" && exit 2
    # swaks exists and runs ok
fi


# =============================================================================
# START SCRIPT PROCESSING
# ------------------------------------


# check docker containers
readonly DOCKERPS="$(docker ps)"

## go through the list of storagenodes
for (( i=0; i<${#NODES[@]}; i++ )); do
NODE=${NODES[$i]}
node_url=${NODEURLS[$i]}

[[ "$VERBOSE" == "true" ]] && echo "==="
[[ "$VERBOSE" == "true" ]] && echo "running the script for node \"$NODE\" (${MOUNTPOINTS[$i]}) .."

## check if node is running in docker
RUNNING="$(echo "$DOCKERPS" 2>&1 | grep "$NODE" -c)"
[[ "$VERBOSE" == "true" ]] && echo " *** node is running        : $RUNNING"


### > check if storagenode is runnning; if not, cancel analysis and push / email alert
if [[ $RUNNING -eq 1 ]]; then
# (if statement is closed at the end of this script)


# grab (real) disk usage

# old: tmp_disk_usage="$(df ${MOUNTPOINTS[$i]} | grep / | awk '{ print $5}' | sed 's/%//g')%"
space_used=$(echo -E $(curl -s "$node_url/api/sno/" | jq '.diskSpace.used'))
space_total=$(echo -E $(curl -s "$node_url/api/sno/" | jq '.diskSpace.available'))
space_trash=$(echo -E $(curl -s "$node_url/api/sno/" | jq '.diskSpace.trash'))
space_overused=$(echo -E $(curl -s "$node_url/api/sno/" | jq '.diskSpace.overused'))
tmp_disk_usage="$(((space_used*100)/(space_total))).$(((space_used*10000)/(space_total)-(((space_used*100)/(space_total))*100)))%"
tmp_disk_gross="$((((space_used+space_trash)*100)/(space_total))).$((((space_used+space_trash)*10000)/(space_total)-((((space_used+space_trash)*100)/(space_total))*100)))%"
[[ "$VERBOSE" == "true" ]] && echo " *** disk usage             : $tmp_disk_usage (incl. trash: $tmp_disk_gross)"
tmp_overused_warning=false
[[ "$VERBOSE" == "true" ]] && [[ $space_overused -gt 0 ]] && echo "warning: space overused is greater than zero!" && $tmp_overused_warning=true


# CHECK SATELLITE SCORES
# ------------------------------------

# check availability of api/sno/satellites
satellite_info_fulltext=$(echo -E $(curl -s "$node_url/api/sno/satellites"))
satellite_scores=$(echo -E $(curl -s "$node_url/api/sno/satellites" |
jq -r \
        --argjson auditScore 0.98 \
        --argjson suspensionScore 0.95 \
        --argjson onlineScore 0.95 \
        '.audits[] as $a | ($a.satelliteName | sub(":.*";"")) as $name |
        reduce ($ARGS.named|keys[]) as $key (
                [];
                if $a[$key] < $ARGS.named[$key] then (
                        . + ["\($key) \(100*$a[$key]|floor)% @ \($name) ... "]
                ) else . end
                ) | .[]'))
[ ! -z "$satellite_info_fulltext" ] && [[ "$VERBOSE" == "true" ]] && echo " *** satellite scores url   : $node_url/api/sno/satellites (OK)"
if [ -z "$satellite_info_fulltext" ] && [[ "$VERBOSE" == "true" ]]
then 
    echo " *** satellite scores url   : $node_url/api/sno/satellites -> not OK"
    echo "warning : satellite scores not available, please verify access."
fi


# CHECK STORJ VERSION
# ------------------------------------

# process, if api info is available, else skip
storj_newer_version=false
storj_version_current=""
storj_version_latest=""
storj_version_date=""

RELEASEDATE=
RELEASEDIFF=

if [ ! -z "$satellite_info_fulltext" ]
then 
    # grab latest version from github
    storj_version_latest=$(curl --silent "https://api.github.com/repos/storj/storj/releases/latest" | jq -r '.tag_name' | cut -c 2-)
    storj_version_date=$(curl --silent "https://api.github.com/repos/storj/storj/releases/latest" | jq -r '.published_at')
    
    RELEASEDATE=$(cut -c1-10 <<< $storj_version_date)
    
    case "${UNAMEOUT}" in
        Linux*)     RELEASEDIFF=$(((`date -d "$TODAY" +%s` - `date -d "$RELEASEDATE" +%s`)/86400));;
        Darwin*)    RELEASEDIFF=$(((`date -jf "%Y-%m-%d" "$TODAY" +%s` - `date -jf "%Y-%m-%d" "$RELEASEDATE" +%s`)/86400));;
        *)          RELEASEDIFF=0
    esac
    
    # grab current version on this node
    storj_version_current=$(echo -E $(curl -s "$node_url/api/sno/" | jq -r '.version'))
    [[ "$VERBOSE" == "true" ]] && echo " *** storj node api url     : $node_url/api/sno (OK)"
    [[ "$VERBOSE" == "true" ]] && echo " *** storj version current  : installed $storj_version_current"
    [[ "$VERBOSE" == "true" ]] && echo " *** storj version latest   : github $storj_version_latest [$RELEASEDATE]"
    if [[ "$storj_version_current" != "$storj_version_latest" ]] && [[ $RELEASEDIFF -gt 10 ]]
    then 
        storj_newer_version=true
        echo "warning : there is a newer version of storj available."
    fi
else
    echo " *** node api url           : $node_url/api/sno -> not OK"
    echo "warning : storj version not available, please verify access."
fi

LOG1D=""
LOG1H=""
NODELOGPATH=${NODELOGPATHS[$i]}
[[ $LOGMIN_OVERRIDE -gt 0 ]] && LOGMIN=$LOGMIN_OVERRIDE
if [[ "$NODELOGPATH" == "/" ]]
then 
    # docker log selection from the last 24 hours and 1 hour
    tmp_logmax="$LOGMAX"
    tmp_logmax+="m"
    LOG1D="$(docker logs $NODE --since $tmp_logmax 2>&1)"
    [[ "$VERBOSE" == "true" ]] && tmp_count="$(echo "$LOG1D" 2>&1 | grep '' -c)"
    [[ "$VERBOSE" == "true" ]] && echo " *** docker log $tmp_logmax selected : #$tmp_count"
    
    tmp_logmin="$LOGMIN"
    tmp_logmin+="m"
    LOG1H="$(docker logs $NODE --since $tmp_logmin 2>&1)"
    [[ "$VERBOSE" == "true" ]] && tmp_count="$(echo "$LOG1H" $NODE 2>&1 | grep '' -c)"
    [[ "$VERBOSE" == "true" ]] && echo " *** docker log $tmp_logmin selected : #$tmp_count"
else
    if [ -r "${MOUNTPOINTS[$i]}${NODELOGPATHS[$i]}" ]; then
        # log file selection, in case log is stored in a file
        LOG1D="$(cat ${MOUNTPOINTS[$i]}${NODELOGPATHS[$i]} | awk -v Date=`date -d 'now - $LOGMAX minutes' +'%Y-%m-%dT%H:%M:%S.000Z'` '$1 > Date')"
        [[ "$VERBOSE" == "true" ]] && tmp_count="$(echo "$LOG1D" 2>&1 | grep '' -c)"
        [[ "$VERBOSE" == "true" ]] && echo " *** log file loaded $LOGMAX minutes : #$tmp_count"
        LOG1H="$(cat ${MOUNTPOINTS[$i]}${NODELOGPATHS[$i]} | awk -v Date=`date -d 'now - $LOGMIN minutes' +'%Y-%m-%dT%H:%M:%S.000Z'` '$1 > Date')"
        [[ "$VERBOSE" == "true" ]] && tmp_count="$(echo "$LOG1H" 2>&1 | grep '' -c)"
        [[ "$VERBOSE" == "true" ]] && echo " *** log file loaded $LOGMIN minutes : #$tmp_count"
    else
        echo "warning : redirected log file does not exist or is not readable:"
        echo "          ${MOUNTPOINTS[$i]}${NODELOGPATHS[$i]}"
    fi
fi

# define audit variables, which are not used, in case there is no audit failure
audit_success=0
audit_failed_warn=0
audit_failed_warn_text=""
audit_failed_crit=0
audit_failed_crit_text=""
audit_recfailrate=0.00%
audit_failrate=0.00%
audit_successrate=100%


# =============================================================================
# SELECT USAGE, ERROR COUNTERS AND ERROR MESSAGES
# ------------------------------------

# select error messages in detail (partially extracted text log)
[[ "$VERBOSE" == "true" ]] && INFO="$(echo "$LOG1H" 2>&1 | grep 'INFO')"
AUDS="$(echo "$LOG1H" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep 'failed')"
FATS="$(echo "$LOG1H" 2>&1 | grep 'FATAL' | grep -v 'INFO')"
ERRS="$(echo "$LOG1H" 2>&1 | grep 'ERROR' | grep -v -e 'INFO' -e 'FATAL' -e 'collector' -e 'piecestore' -e 'pieces error: filestore error: context canceled' -e 'piecedeleter' -e 'emptying trash failed' -e 'service ping satellite failed' -e 'timeout: no recent network activity')"

# added "severe" errors in order to recognize e.g. docker issues, connectivity issues etc.
SEVERE="$(echo "$LOG1H" 2>&1 | grep -i -e 'error:' -e 'fatal:' -e 'unexpected shutdown' -e 'fatal error' -e 'transport endpoint is not connected' -e 'Unable to read the disk' -e 'software caused connection abort' | grep -v -e 'emptying trash failed' -e 'INFO' -e 'FATAL' -e 'collector' -e 'piecestore' -e 'pieces error: filestore error: context canceled' -e 'piecedeleter' -e 'emptying trash failed' -e 'service ping satellite failed' -e 'timeout: no recent network activity')"

# count errors 
[[ "$VERBOSE" == "true" ]] && tmp_info="$(echo "$INFO" 2>&1 | grep 'INFO' -c)"
tmp_fatal_errors="$(echo "$FATS" 2>&1 | grep 'FATAL' -c)"
tmp_audits_failed="$(echo "$AUDS" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep 'failed' -c)"
tmp_rest_of_errors="$(echo "$ERRS" 2>&1 | grep 'ERROR' -c)"
tmp_io_errors="$(echo "$ERRS" 2>&1 | grep 'ERROR' | grep -e 'timeout' -c)"
temp_severe_errors="$(echo "$SEVERE" 2>&1 | grep -i -e 'error:' -e 'fatal:' -e 'unexpected shutdown' -e 'fatal error' -e 'transport endpoint is not connected' -e 'Unable to read the disk' -e 'software caused connection abort' -c)"

[[ "$VERBOSE" == "true" ]] && echo " *** info count             : #$tmp_info"
[[ "$VERBOSE" == "true" ]] && echo " *** audit error count      : #$tmp_audits_failed"
[[ "$VERBOSE" == "true" ]] && echo " *** fatal error count      : #$tmp_fatal_errors"
[[ "$VERBOSE" == "true" ]] && echo " *** severe count           : #$temp_severe_errors"
[[ "$VERBOSE" == "true" ]] && echo " *** other error count      : #$tmp_rest_of_errors"
[[ "$VERBOSE" == "true" ]] && echo " *** i/o timouts count      : #$tmp_io_errors"


## in case of audit issues, select and share details (recoverable or critical)
# ------------------------------------

#count of started audits
audit_started=$(echo "$LOG1D" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep started -c)
#count of successful audits
audit_success=$(echo "$LOG1D" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep downloaded -c)
#count of recoverable failed audits
audit_failed_warn=$(echo "$LOG1D" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep failed | grep -v exist -c)
audit_failed_warn_text=$(echo "$LOG1H" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep failed | grep -v exist)
#count of unrecoverable failed audits
audit_failed_crit=$(echo "$LOG1D" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep failed | grep exist -c)
audit_failed_crit_text=$(echo "$LOG1H" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep failed | grep exist)
if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
then
	audit_recfailrate=$(printf '%.2f\n' $(echo -e "$audit_failed_warn $audit_success $audit_failed_crit" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
fi
if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
then
	audit_failrate=$(printf '%.2f\n' $(echo -e "$audit_failed_crit $audit_failed_warn $audit_success" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
fi
if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
then
    audit_successrate=$(printf '%.2f\n' $(echo -e "$audit_success $audit_failed_crit $audit_failed_warn" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
    audit_successrate=0.000%
fi
#check difference started - success - failed
audit_difference=0
if [[ $audit_started -gt 0 ]]
then 
    # there are audits, which have been started, but are not finished
    # more than 2 pending audits = warning alert to be sent
    audit_difference=$(($audit_started-$audit_success-$audit_failed_crit-$audit_failed_warn))
fi

[[ "$VERBOSE" == "true" ]] && echo " *** audits                 : warn: $audit_recfailrate, crit: $audit_failrate, s: $audit_successrate"
if [[ "$VERBOSE" == "true" ]] && [[ $audit_difference -gt 0 ]]; then
                              echo "warning:                      -> there are audits pending and not finished ($audit_difference)"
fi

## download stats
# ------------------------------------

#count of successful downloads
dl_success=$(echo "$LOG1D" 2>&1 | grep '"GET"' | grep 'downloaded' -c)
#canceled Downloads from your node
dl_canceled=$(echo "$LOG1D" 2>&1 | grep '"GET"' | grep 'download canceled' -c)
#Failed Downloads from your node
dl_failed=$(echo "$LOG1D" 2>&1 | grep '"GET"' | grep 'download failed' -c)
#Ratio of canceled Downloads
if [ $(($dl_success+$dl_failed+$dl_canceled)) -ge 1 ]
then
	dl_canratio=$(printf '%.2f\n' $(echo -e "$dl_canceled $dl_success $dl_failed" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	dl_canratio=0.000%
fi
#Ratio of Failed Downloads
if [ $(($dl_success+$dl_failed+$dl_canceled)) -ge 1 ]
then
	dl_failratio=$(printf '%.2f\n' $(echo -e "$dl_failed $dl_success $dl_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	dl_failratio=0.000%
fi
#Ratio of Successful Downloads
get_ratio_int=0
if [ $(($dl_success+$dl_failed+$dl_canceled)) -ge 1 ]
then
	get_ratio_int=$(printf '%.0f\n' $(echo -e "$dl_success $dl_failed $dl_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
[[ "$VERBOSE" == "true" ]] && echo " *** downloads              : c: $dl_canratio, f: $dl_failratio, s: $get_ratio_int%"


## upload stats
# ------------------------------------

#count of successful uploads to your node
put_success=$(echo "$LOG1D" 2>&1 | grep '"PUT"' | grep uploaded -c)
#count of rejected uploads to your node
put_rejected=$(echo "$LOG1D" 2>&1 | grep 'upload rejected' -c)
#count of canceled uploads to your node
put_canceled=$(echo "$LOG1D" 2>&1 | grep '"PUT"' | grep 'upload canceled' -c)
#count of failed uploads to your node
put_failed=$(echo "$LOG1D" 2>&1 | grep '"PUT"' | grep 'upload failed' -c)
#Ratio of Rejections
if [ $(($put_success+$put_rejected+$put_canceled+$put_failed)) -ge 1 ]
then
	put_accept_ratio=$(printf '%.2f\n' $(echo -e "$put_rejected $put_success $put_canceled $put_failed" | awk '{print ( ($2 + $3 + $4) / ( $1 + $2 + $3 + $4 )) * 100 }'))%
else
	put_accept_ratio=0.000%
fi
#Ratio of Failed
if [ $(($put_success+$put_rejected+$put_canceled+$put_failed)) -ge 1 ]
then
	put_fail_ratio=$(printf '%.2f\n' $(echo -e "$put_failed $put_success $put_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	put_fail_ratio=0.000%
fi
#Ratio of canceled
if [ $(($put_success+$put_rejected+$put_canceled+$put_failed)) -ge 1 ]
then
	put_cancel_ratio=$(printf '%.2f\n' $(echo -e "$put_canceled $put_failed $put_success" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	put_cancel_ratio=0.000%
fi
#Ratio of Success
put_ratio_int=0
if [ $(($put_success+$put_canceled+$put_failed)) -ge 1 ]
then
	put_ratio_int=$(printf '%.0f\n' $(echo -e "$put_success $put_failed $put_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
[[ "$VERBOSE" == "true" ]] && echo " *** uploads                : c: $put_cancel_ratio, f: $put_fail_ratio, s: $put_ratio_int%"


## repair download & upload stats
# ------------------------------------

#count of started downloads of pieces for repair process
get_repair_started=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep "download started" -c)
#count of successful downloads of pieces for repair process
get_repair_success=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep downloaded -c)
#count of failed downloads of pieces for repair process
get_repair_failed=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep 'download failed' -c)
#count of canceled downloads of pieces for repair process
get_repair_canceled=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep 'download canceled' -c)
#Ratio of Fail GET_REPAIR
if [ $(($get_repair_success+$get_repair_failed+$get_repair_canceled)) -ge 1 ]
then
	get_repair_failratio=$(printf '%.2f\n' $(echo -e "$get_repair_failed $get_repair_success $get_repair_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	get_repair_failratio=0.000%
fi
#Ratio of Cancel GET_REPAIR
if [ $(($get_repair_success+$get_repair_failed+$get_repair_canceled)) -ge 1 ]
then
	get_repair_canratio=$(printf '%.2f\n' $(echo -e "$get_repair_canceled $get_repair_success $get_repair_failed" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	get_repair_canratio=0.000%
fi
#Ratio of Success GET_REPAIR
get_repair_ratio_int=0
if [ $(($get_repair_success+$get_repair_failed+$get_repair_canceled)) -ge 1 ]
then
	get_repair_ratio_int=$(printf '%.0f\n' $(echo -e "$get_repair_success $get_repair_failed $get_repair_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
[[ "$VERBOSE" == "true" ]] && echo " *** repair downloads       : c: $get_repair_canratio, f: $get_repair_failratio, s: $get_repair_ratio_int%"

#count of started uploads of repaired pieces
put_repair_started=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep "upload started" -c)
#count of successful uploads of repaired pieces
put_repair_success=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep uploaded -c)
#count of canceled uploads repaired pieces
put_repair_canceled=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep 'upload canceled' -c)
#count of failed uploads repaired pieces
put_repair_failed=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep 'upload failed' -c)
#Ratio of Fail PUT_REPAIR
if [ $(($put_repair_success+$put_repair_failed+$put_repair_canceled)) -ge 1 ]
then
	put_repair_failratio=$(printf '%.2f\n' $(echo -e "$put_repair_failed $put_repair_success $put_repair_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	put_repair_failratio=0.000%
fi
#Ratio of Cancel PUT_REPAIR
if [ $(($put_repair_success+$put_repair_failed+$put_repair_canceled)) -ge 1 ]
then
	put_repair_canratio=$(printf '%.2f\n' $(echo -e "$put_repair_canceled $put_repair_success $put_repair_failed" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	put_repair_canratio=0.000%
fi
#Ratio of Success PUT_REPAIR
put_repair_ratio_int=0
if [ $(($put_repair_success+$put_repair_failed+$put_repair_canceled)) -ge 1 ]
then
	put_repair_ratio_int=$(printf '%.0f\n' $(echo -e "$put_repair_success $put_repair_failed $put_repair_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
[[ "$VERBOSE" == "true" ]] && echo " *** repair uploads         : c: $put_repair_canratio, f: $put_repair_failratio, s: $put_repair_ratio_int%"


## count upload and download activity last hour
# ------------------------------------

gets_recent_hour=$(echo "$LOG1H" 2>&1 | grep '"GET"' -c)
puts_recent_hour=$(echo "$LOG1H" 2>&1 | grep '"PUT"' -c)
tmp_no_getput_1h=false
[[ $gets_recent_hour -eq 0 ]] && tmp_no_getput_1h=true
[[ $puts_recent_hour -eq 0 ]] && tmp_no_getput_1h=true
tmp_no_getput_ok="OK"
[[ "$tmp_no_getput_1h" == "true" ]] && tmp_no_getput_ok="NOK"
[[ "$VERBOSE" == "true" ]] && echo " *** $LOGMIN m activity : up: $gets_recent_hour / down: $puts_recent_hour > $tmp_no_getput_ok"


# ignore i/o timeouts (satellite service pings + single satellite connects), if audit success rate is 100% and there are no other errors as well
ignore_rest_of_errors=false
if [[ $tmp_io_errors -ne 0 ]]; then
	if [[ $tmp_rest_of_errors -eq $tmp_io_errors ]]; then
		ignore_rest_of_errors=true
	else
		ignore_rest_of_errors=false
	fi
else
	ignore_rest_of_errors=false
fi
# never ignore in case of audit issues
if [[ $tmp_audits_failed -ne 0 ]]; then
	ignore_rest_of_errors=false
fi
[[ "$VERBOSE" == "true" ]] && echo " *** i/o timouts ignored    : $ignore_rest_of_errors"


# =============================================================================
# CONCATENATE THE PUSH MESSAGE
# ------------------------------------

#reset DLOG
DLOG=""

if [[ $tmp_fatal_errors -eq 0 ]] && [[ $tmp_io_errors -eq $tmp_rest_of_errors ]] && [[ $tmp_audits_failed -eq 0 ]] && [[ $temp_severe_errors -eq 0 ]]; then 
	DLOG="$DLOG [$NODE] : hdd $tmp_disk_gross > OK "
else
	DLOG="**warning** [$NODE] : "
fi

if [[ $tmp_audits_failed -ne 0 ]]; then
	DLOG="$DLOG audit issues ($tmp_audits_failed; recoverable: $audit_recfailrate; critical: $audit_failrate)"
fi

if [[ $audit_difference -gt 1 ]]; then
	DLOG="$DLOG audit warning (pending: $audit_difference)"
fi

if [[ $temp_severe_errors -ne 0 ]]; then
	DLOG="$DLOG severe issues ($temp_severe_errors)"
fi

if [[ $tmp_fatal_errors -ne 0 ]]; then
	DLOG="$DLOG fatal issues ($tmp_fatal_errors)"
fi

if [[ $tmp_rest_of_errors -ne 0 ]]; then
	if [[ $tmp_io_errors -ne $tmp_rest_of_errors ]]; then
		DLOG="$DLOG other issues ($tmp_rest_of_errors)"
	else
		DLOG="$DLOG (skipped io)"
	fi
fi

if [[ "$tmp_overused_warning" == "true" ]] ; then
    DLOG="$DLOG; \n.. space warning : overused"
fi


if [ $get_repair_started -ne 0 -a \( $get_repair_ratio_int -lt 95 -o $put_repair_ratio_int -lt 95 \) ]; then
	DLOG="$DLOG; \n.. warning !! rep ↓ $get_repair_ratio_int / ↑ $put_repair_ratio_int \n-> risk of getting disqualified"
fi

if [[ $gets_recent_hour -eq 0 ]] && [[ $puts_recent_hour -eq 0 ]]; then
	DLOG="$DLOG; \n.. warning !! no get/put in last $LOGMINm"
fi

if [[ $get_ratio_int -lt 90 ]] || [[ $put_ratio_int -lt 90 ]]; then
	DLOG="$DLOG; \n.. warning !! ↓ $get_ratio_int / ↑ $put_ratio_int low"
fi

if [[ "$storj_newer_version" == "true" ]] ; then
    DLOG="$DLOG; \n.. new version : $storj_version_current > $storj_version_latest" #  [$storj_version_date]
fi


# =============================================================================
# ECHO OUTPUT IN CASE COMMAND LINE USAGE (in debug modes)
# ------------------------------------

# dlog echo to terminal
[[ "$VERBOSE" == "true" ]] && echo "==="
[[ "$VERBOSE" == "true" ]] && echo " message: $DLOG"


if [[ "$VERBOSE" == "true" ]] ; then
	# log excerpt echo
	if [[ $tmp_rest_of_errors -ne 0 ]]; then 
		echo "==="
		echo "ERRORS"
		echo "$ERRS"
	fi
	if [[ $tmp_fatal_errors -ne 0 ]]; then 
		echo "==="
		echo "FATAL ERRORS"
		echo "$FATS"
	fi
	if [[ $tmp_audits_failed -ne 0 ]]; then 
		echo "==="
		echo "AUDIT"
		echo "$AUDS"
	fi
	if [ ! -z "$satellite_scores" ]; then
		echo "==="
		echo "SATELLITE SCORES"
		echo "$satellite_scores"
	fi
	if [[ $temp_severe_errors -ne 0 ]]; then
		echo "==="
		echo "SEVERE ERRORS"
		echo "$SEVERE"
	fi
	echo "==="
fi



# =============================================================================
# SEND THE PUSH MESSAGE TO DISCORD
# ------------------------------------

cd $DIR

if [[ "$DISCORDON" == "true" ]]; then
# send discord push

#[[ $tmp_fatal_errors -ne 0 ]] && echo true || echo false
#[[ $tmp_io_errors -ne $tmp_rest_of_errors ]] && echo true || echo false
#[[ $tmp_audits_failed -ne 0 ]] && echo true || echo false
#[[ $temp_severe_errors -ne 0 ]] && echo true || echo false
#[[ $put_repair_ratio_int -lt 95 ]] && echo true || echo false
#[[ $get_repair_started -ne 0 ]] && echo true || echo false
#[[ $get_repair_ratio_int -lt 95 ]] && echo true || echo false # --> true
#[[ $get_ratio_int -lt 90 ]] && echo true || echo false
#[[ $put_ratio_int -lt 90 ]] && echo true || echo false
#[[ "$tmp_no_getput_1h" == "true" ]] && echo true || echo false # --> true
#[[ $DEB -eq 1 ]] && echo true || echo false

if [ $tmp_fatal_errors -ne 0 -o $tmp_io_errors -ne $tmp_rest_of_errors -o $tmp_audits_failed -ne 0 -o $temp_severe_errors -ne 0 -o $put_repair_ratio_int -lt 95 -o \( $get_repair_started -ne 0 -a $get_repair_ratio_int -lt 95 \) -o $get_ratio_int -lt 90 -o $put_ratio_int -lt 90 -o "$tmp_no_getput_1h" == "true" -o $DEB -eq 1 ]; then 
    { ./discord.sh --webhook-url="$DISCORDURL" --username "health check" --text "$DLOG"; } 2>/dev/null
    [[ "$VERBOSE" == "true" ]] && echo " *** discord summary push sent."
fi
# separated satellites push from errors, occured last $LOGMIN - as scores last "longer"
# and push frequency limited by $satellite_notification anyway
if [ ! -z "$satellite_scores" ] && [[ "$satellite_notification" == "true" ]] && [[ "$DISCORDON" == "true" ]]
then
    { ./discord.sh --webhook-url="$DISCORDURL" --username "satellites warning" --text "[$NODE]: $satellite_scores"; } 2>/dev/null
    [[ "$VERBOSE" == "true" ]] && echo " *** discord satellite push sent."
fi
# in case of discord debug mode is on, also send success statistics
if [[ $DEB -eq 1 ]] && [[ "$DISCORDON" == "true" ]]
then
    { ./discord.sh --webhook-url="$DISCORDURL" --username "one-day stats" --text "[$NODE]\n.. audits (r: $audit_recfailrate, c: $audit_failrate, s: $audit_successrate)\n.. downloads (c: $dl_canratio, f: $dl_failratio, s: $get_ratio_int%)\n.. uploads (c: $put_cancel_ratio, f: $put_fail_ratio, s: $put_ratio_int%)\n.. rep down (c: $get_repair_canratio, f: $get_repair_failratio, s: $get_repair_ratio_int%)\n.. rep up (c: $put_repair_canratio, f: $put_repair_failratio, s: $put_repair_ratio_int%)"; } 2>/dev/null
    [[ "$VERBOSE" == "true" ]] && echo " *** discord success rates push sent."
fi
fi


# =============================================================================
# SEND EMAIL ALERTS WITH ERROR DETAILS (and debug mail to verify mail works)
# ------------------------------------

# send email alerts
if [[ "$MAILON" == "true" ]]; then

if [ ! -z "$satellite_scores" ] && [[ "$satellite_notification" == "true" ]]; then
    swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : SATELLITE SCORES BELOW THRESHOLD" --body "$satellite_scores" --silent "1"
	[[ "$VERBOSE" == "true" ]] && echo " *** satellite warning mail sent."
fi
if [[ $tmp_fatal_errors -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : FATAL ERRORS FOUND" --body "$FATS" --silent "1"
	[[ "$VERBOSE" == "true" ]] && echo " *** fatal error mail sent."
fi
if [[ $temp_severe_errors -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : SEVERE ERRORS FOUND" --body "$SEVERE" --silent "1"
	[[ "$VERBOSE" == "true" ]] && echo " *** severe error mail sent."
fi
if [[ $tmp_rest_of_errors -ne 0 ]]; then
	if [[ "$ignore_rest_of_errors" == "true" ]]; then
		if [[ $DEB -eq 1 ]]; then
			swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : OTHER ERRORS FOUND" --body "$ERRS" --silent "1"
			[[ "$VERBOSE" == "true" ]] && echo " *** general error mail sent (ignore case: $ignore_rest_of_errors)."
		fi
	else
		swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : OTHER ERRORS FOUND" --body "$ERRS" --silent "1"
		[[ "$VERBOSE" == "true" ]] && echo " *** general error mail sent (ignore case: $ignore_rest_of_errors)."
	fi
fi
if [[ $tmp_audits_failed -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : AUDIT ERRORS FOUND" --body "Recoverable: $audit_recfailrate \n\n$audit_failed_warn_text \n\nCritical: $audit_failrate \n\n$audit_failed_crit_text" --silent "1"
	[[ "$VERBOSE" == "true" ]] && echo " *** audit error mail sent."
fi
if [[ $audit_difference -gt 1 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : AUDIT WARNING - pending audits" --body "Warning: there are $audit_difference pending audits, which have not yet been finished." --silent "1"
	[[ "$VERBOSE" == "true" ]] && echo " *** pending audit warning mail sent."
fi

# send debug mail 
if [[ $DEB -eq 2 ]]; then
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : DEBUG TEST MAIL" --body "blobb." --silent "1"
	[[ "$VERBOSE" == "true" ]] && echo " *** debut mail sent."
fi

fi


### > check if storagenode is runnning; if not, cancel analysis and push alert
###   email alert comes automatically through uptimerobot-ping alert. 
###   if relevant for you, enable the mail alert below.
else
	[[ "$VERBOSE" == "true" ]] && echo "warning: $NODE not running."
	if [[ "$DISCORDON" == "true" ]]; then
	    cd $DIR
	    { ./discord.sh --webhook-url="$DISCORDURL" --username "storj stats" --text "**warning :** $NODE not running!"; } 2>/dev/null
	fi
	#swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "$NODE : NOT RUNNING" --body "warning: storage node is not running." --silent "1"
fi

done # end of while command of storagenodes list
