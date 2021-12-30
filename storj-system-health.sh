#!/usr/bin/env bash
#
# v1.4.0
#
# storj-system-health.sh - storagenode health checks and notifications to discord / by email
# by dusselmann, https://github.com/dusselmann/storj-system-health.sh
# This script is licensed under GNU GPL version 3.0 or above
# 
# > requires discord.sh from https://github.com/ChaoticWeg/discord.sh
# > uses parts of storj_success_rate from https://github.com/ReneSmeekes/storj_success_rate
# 
# -------------------------------------------------------------------------


# =============================================================================
# DEFINE VARIABLES AND CONSTANTS
# ------------------------------------

## discord settings
DISCORDON=true			# enables (true) or disables (false) discord pushes
URL='https://discord.com/api/webhooks/...' 
				# your discord webhook url

## mail settings
MAILON=true			# enables (true) or disables (false) email messages
MAILFROM=""                     # your "from:" mail address
MAILTO=""                       # your "to:" mail address
MAILSERVER=""                   # your smtp server address
MAILUSER=""                     # your user name from smtp server
MAILPASS=""                     # your password from smtp server

## node data mount point
MOUNTPOINT="/mnt/node"          # your storage node mount point

## storj node docker names
## in case multinodes are used, just add them es separate strings
NODES=(
	"storagenode"
	#"storagenode-2"
	#"storagenode-3"
)


# =============================================================================
# DEBUG MODE ON / OFF
# ------------------------------------

if [ $# -ge 2 ]
then
	DEB=2
	echo -e ".. mail debug mode on"
elif [ $# -ge 1 ]
then 
	DEB=1
	echo -e ".. discord debug mode on"
else
	DEB=0
	echo -e ".. debug mode off"
fi


# =============================================================================
# CHECK DEPENDENCIES AND LIBRARIES
# ------------------------------------


# check for jq

jq --version >/dev/null 2>&1
jq_ok=$?

[[ "$jq_ok" -eq 127 ]] && \
    echo "fatal: jq not installed" && exit 2
[[ "$jq_ok" -ne 0 ]] && \
    echo "fatal: unknown error in jq" && exit 2

# jq exists and runs ok


# check for curl
curl --version >/dev/null 2>&1
curl_ok=$?

[[ "$curl_ok" -eq 127 ]] && \
    echo "fatal: curl not installed" && exit 2
# curl exists and runs ok


# check for swaks
swaks --version >/dev/null 2>&1
swaks_ok=$?

[[ "$swaks_ok" -eq 127 ]] && \
    echo "fatal: swaks not installed" && exit 2
# swaks exists and runs ok


# =============================================================================
# HELP TEXT
# ------------------------------------


help_text="Usage: storj-system-health.sh [OPTIONS]

General options:
  --help                         Display this help and exit"
  
# HELP TEXT PLEASE
# [[ "$#" -eq 0 ]] && echo "$help_text" && exit 0
[[ "${1}" == "help" ]] && echo "$help_text" && exit 0
[[ "${1}" == "--help" ]] && echo "$help_text" && exit 0



# =============================================================================
# START SCRIPT PROCESSING
# ------------------------------------


# let the script run in low performance to not block the system
renice 19 $$ 

# check docker containers
DOCKERPS="$(docker ps)"
# grab (real) disk usage
tmp_disk_usage="$(df $MOUNTPOINT | grep / | awk '{ print $5}' | sed 's/%//g')%"


## go through the list of storagenodes
for NODE in "${NODES[@]}"; do

echo "running the script for node \"$NODE\" .."

## check if node is running in docker
RUNNING="$(echo "$DOCKERPS" 2>&1 | grep "$NODE" -c)"
echo ".. node is running : $RUNNING"

# docker log selection from the last 24 hours and 1 hour
LOG1D="$(docker logs --since "$(date -d "$date -1 day" +"%Y-%m-%dT%H:%M")" $NODE 2>&1)"
echo ".. docker log 1d selected."
LOG1H="$(docker logs --since "$(date -d "$date -1 hour" +"%Y-%m-%dT%H:%M")" $NODE 2>&1)"
echo ".. docker log 1h selected."

# define audit variables, which are not used, in case there is no audit failure
audit_success=0
audit_failed_warn=0
audit_failed_warn_text=""
audit_failed_crit=0
audit_failed_crit_text=""
audit_recfailrate=0.000%
audit_failrate=0.000%


### > check if storagenode is runnning; if not, cancel analysis and push / email alert
if [[ $RUNNING -eq 1 ]]; then
# (if statement is closed at the end of this script)


# =============================================================================
# SELECT USAGE, ERROR COUNTERS AND ERROR MESSAGES
# ------------------------------------

# select error messages in detail (partially extracted text log)
DLOG=""
#INFO="$(echo "$LOG1H" 2>&1 | grep 'INFO' | grep -v -e 'FATAL' -e 'ERROR')"
AUDS="$(echo "$LOG1H" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep 'failed')"
FATS="$(echo "$LOG1H" 2>&1 | grep 'FATAL' | grep -v 'INFO')"
ERRS="$(echo "$LOG1H" 2>&1 | grep 'ERROR' | grep -v -e 'collector' -e 'piecestore' -e 'pieces error: filestore error: context canceled' -e 'piecedeleter')"

# count errors 
#tmp_info="$(echo "$INFO" 2>&1 | grep 'INFO' -c)"
tmp_fatal_errors="$(echo "$FATS" 2>&1 | grep 'FATAL' -c)"
tmp_audits_failed="$(echo "$AUDS" 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep 'failed' -c)"
tmp_rest_of_errors="$(echo "$ERRS" 2>&1 | grep 'ERROR' -c)"
tmp_io_errors="$(echo "$ERRS" 2>&1 | grep 'ERROR' | grep -e 'i/o timeout' | grep -e 'ping satellite' -c)"

#echo "info $tmp_info"
echo ".. audit error count : $tmp_audits_failed"
echo ".. fatal error count : $tmp_fatal_errors"
echo ".. other error count : $tmp_rest_of_errors"
echo ".. i/o timouts count : $tmp_io_errors"


## in case of audit issues, select and share details (recoverable or critical)
# ------------------------------------
if [[ $tmp_audits_failed -ne 0 ]]; then 
	#count of successful audits
	audit_success=$(echo "$LOG1D" 2>&1 | grep GET_AUDIT | grep downloaded -c)
	#count of recoverable failed audits
	audit_failed_warn=$(echo "$LOG1D" 2>&1 | grep GET_AUDIT | grep failed | grep -v exist -c)
	audit_failed_warn_text=$(echo "$LOG1D" 2>&1 | grep GET_AUDIT | grep failed | grep -v exist)
	#count of unrecoverable failed audits
	audit_failed_crit=$(echo "$LOG1D" 2>&1 | grep GET_AUDIT | grep failed | grep exist -c)
	audit_failed_crit_text=$(echo "$LOG1D" 2>&1 | grep GET_AUDIT | grep failed | grep exist)
	if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
	then
		audit_recfailrate=$(printf '%.3f\n' $(echo -e "$audit_failed_warn $audit_success $audit_failed_crit" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
	fi
	if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
	then
		audit_failrate=$(printf '%.3f\n' $(echo -e "$audit_failed_crit $audit_failed_warn $audit_success" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
	fi
fi
echo ".. stats selected : audits"


## download stats
# ------------------------------------

#count of successful downloads
dl_success=$(echo "$LOG1D" 2>&1 | grep '"GET"' | grep 'downloaded' -c)
#canceled Downloads from your node
dl_canceled=$(echo "$LOG1D" 2>&1 | grep '"GET"' | grep 'download canceled' -c)
#Failed Downloads from your node
dl_failed=$(echo "$LOG1D" 2>&1 | grep '"GET"' | grep 'download failed' -c)
#Ratio of Successful Downloads
get_ratio_int=0
if [ $(($dl_success+$dl_failed+$dl_canceled)) -ge 1 ]
then
	get_ratio_int=$(printf '%.0f\n' $(echo -e "$dl_success $dl_failed $dl_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
echo ".. stats selected : downloads"


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
#Ratio of Success
put_ratio_int=0
if [ $(($put_success+$put_canceled+$put_failed)) -ge 1 ]
then
	put_ratio_int=$(printf '%.0f\n' $(echo -e "$put_success $put_failed $put_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
echo ".. stats selected : uploads"


## repair download & upload stats
# ------------------------------------

#count of successful downloads of pieces for repair process
get_repair_success=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep downloaded -c)
#count of failed downloads of pieces for repair process
get_repair_failed=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep 'download failed' -c)
#count of canceled downloads of pieces for repair process
get_repair_canceled=$(echo "$LOG1D" 2>&1 | grep GET_REPAIR | grep 'download canceled' -c)
#Ratio of Success GET_REPAIR
get_repair_ratio_int=0
if [ $(($get_repair_success+$get_repair_failed+$get_repair_canceled)) -ge 1 ]
then
	get_repair_ratio_int=$(printf '%.0f\n' $(echo -e "$get_repair_success $get_repair_failed $get_repair_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
echo ".. stats selected : repair downloads"

#count of successful uploads of repaired pieces
put_repair_success=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep uploaded -c)
#count of canceled uploads repaired pieces
put_repair_canceled=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep 'upload canceled' -c)
#count of failed uploads repaired pieces
put_repair_failed=$(echo "$LOG1D" 2>&1 | grep PUT_REPAIR | grep 'upload failed' -c)
#Ratio of Success PUT_REPAIR
put_repair_ratio_int=0
if [ $(($put_repair_success+$put_repair_failed+$put_repair_canceled)) -ge 1 ]
then
	put_repair_ratio_int=$(printf '%.0f\n' $(echo -e "$put_repair_success $put_repair_failed $put_repair_canceled" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))
fi
echo ".. stats selected : repair uploads"


## count upload and download activity last hour
# ------------------------------------

gets_recent_hour=$(echo "$LOG1H" 2>&1 | grep '"GET"' -c)
puts_recent_hour=$(echo "$LOG1H" 2>&1 | grep '"PUT"' -c)
tmp_no_getput_1h=false
[[ $gets_recent_hour -eq 0 ]] && tmp_no_getput_1h=true
[[ $puts_recent_hour -eq 0 ]] && tmp_no_getput_1h=true
echo ".. stats selected : 1h activity (no activity : $tmp_no_getput_1h)"


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
echo ".. stats selected : i/o timouts > other errors ignored : $ignore_rest_of_errors"


# =============================================================================
# CONCATENATE THE PUSH MESSAGE
# ------------------------------------

if [[ $tmp_fatal_errors -eq 0 ]] && [[ $tmp_io_errors -eq $tmp_rest_of_errors ]] && [[ $tmp_audits_failed -eq 0 ]]; then 
	DLOG="**health check :** hdd $tmp_disk_usage; OK"
else
	DLOG="**warning :**"
fi

if [[ $tmp_audits_failed -ne 0 ]]; then
	DLOG="$DLOG **AUDIT ERRORS** ($tmp_audits_failed; recoverable: $audit_recfailrate; critical: $audit_failrate);"
fi

if [[ $tmp_fatal_errors -ne 0 ]]; then
	DLOG="$DLOG **FATAL ERRORS** ($tmp_fatal_errors);"
fi

if [[ $tmp_rest_of_errors -ne 0 ]]; then
	if [[ $tmp_io_errors -ne $tmp_rest_of_errors ]]; then
		DLOG="$DLOG **ERRORS FOUND** ($tmp_rest_of_errors);"
	else
		DLOG="$DLOG (skipped io)"
	fi
fi

if [[ $get_repair_ratio_int -lt 95 ]] || [[ $put_repair_ratio_int -lt 95 ]]; then
	DLOG="$DLOG; \nattention !! repair stats below threshold (download $get_repair_ratio_int / upload $put_repair_ratio_int: risk of getting disqualified)"
fi

if [[ $gets_recent_hour -eq 0 ]] && [[ $puts_recent_hour -eq 0 ]]; then
	DLOG="$DLOG; \nattention !! no get/put in last 1h - beware"
fi

if [[ $get_ratio_int -lt 90 ]] || [[ $put_ratio_int -lt 90 ]]; then
	DLOG="$DLOG; \nattention !! get/put success ratio below threshold - beware (download $get_ratio_int / upload $put_ratio_int)"
fi
echo ".. alert message prepared:"


# =============================================================================
# ECHO OUTPUT IN CASE COMMAND LINE USAGE (in debug modes)
# ------------------------------------

# dlog echo to terminal
echo "==="
echo "$DLOG"

if [[ $DEB -ne 0 ]]; then
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
fi



# =============================================================================
# SEND THE PUSH MESSAGE TO DISCORD
# ------------------------------------

# send discord ping
if [[ $tmp_fatal_errors -ne 0 ]] || [[ $tmp_io_errors -ne $tmp_rest_of_errors ]] || [[ $tmp_audits_failed -ne 0 ]] || [[ $get_repair_ratio_int -lt 95 ]] || [[ $put_repair_ratio_int -lt 95 ]] || [[ $get_ratio_int -lt 90 ]] || [[ $put_ratio_int -lt 90 ]] || $tmp_no_getput_1h || [[ $DEB -eq 1 ]]; then 
    if $DISCORDON; then
        ./discord.sh --webhook-url="$URL" --username "storj stats" --text "$DLOG"
        echo ".. discord push sent."
    fi
fi

# echo "fatal: $tmp_fatal_errors \n others: $tmp_rest_of_errors \n audits: $tmp_audits_failed \n getrepair: $get_repair_ratio_int \n putrepair: $put_repair_ratio_int \n download: $get_ratio_int \n upload: $put_ratio_int \n no_getput: $tmp_no_getput_1h \n ignore: $ignore_rest_of_errors \n debug: $DEB"


# =============================================================================
# SEND EMAIL ALERTS WITH ERROR DETAILS (and debug mail to verify mail works)
# ------------------------------------

# send email alerts
if $MAILON; then

if [[ $tmp_fatal_errors -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : FATAL ERRORS FOUND" --body "$FATS" --silent "1"
	echo ".. fatal error mail sent."
fi
if [[ $tmp_rest_of_errors -ne 0 ]]; then
	if $ignore_rest_of_errors; then
		if [[ $DEB -eq 1 ]]; then
			swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : OTHER ERRORS FOUND" --body "$ERRS" --silent "1"
			echo ".. general error mail sent (ignore: $ignore_rest_of_errors)."
		fi
	else
		swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : OTHER ERRORS FOUND" --body "$ERRS" --silent "1"
		echo ".. general error mail sent (ignore: $ignore_rest_of_errors)."
	fi
fi
if [[ $tmp_audits_failed -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : AUDIT ERRORS FOUND" --body "Recoverable: $audit_recfailrate \n\n$audit_failed_warn_text \n\nCritical: $audit_failrate \n\n$audit_failed_crit_text\n\nComplete: \n$AUDS \n\n$AUDS" --silent "1"
	echo ".. audit error mail sent."
fi
# send debug mail 
if [[ $DEB -eq 2 ]]; then
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : DEBUG TEST MAIL" --body "blobb." --silent "1"
	echo ".. debut mail sent."
fi

fi


### > check if storagenode is runnning; if not, cancel analysis and push alert
###   email alert comes automatically through uptimerobot-ping alert. 
###   if relevant for you, enable the mail alert below.
else
	if $DISCORDON; then
	./discord.sh --webhook-url="$URL" --username "storj stats" --text "**warning :** storagenode not running!"
	fi
	#swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : NOT RUNNING" --body "warning: storage node is not running." --silent "1"
fi

done # end of while command of storagenodes list
