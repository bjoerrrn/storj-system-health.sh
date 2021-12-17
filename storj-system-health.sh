#!/usr/bin/env bash

#
# storj-system-health.sh - storagenode health checks and notifications to discord / by email
# by dusselmann, https://github.com/dusselmann/storj-system-health.sh


# define variables
## discord webhook url
URL='https://discord.com/api/webhooks/...'    # your discord webhook url
## mail variables
MAILFROM=""                                   # your "from:" mail address
MAILTO=""                                     # your "to:" mail address
MAILSERVER=""                                 # your smtp server address
MAILUSER=""                                   # your user name from smtp server
MAILPASS=""                                   # your password from smtp server
MAILEOF=".. end of mail."
## node data mount point
MOUNTPOINT="/mnt/node"                        # your storage node mount point
## storj node docker name
NODENAME="storagenode"                        # your storagenode docker name


# check if debug params exists or not
if [ $# -ge 2 ]
then
	DEB=2
	echo -e "mail debug mode on"
elif [ $# -ge 1 ]
then 
	DEB=1
	echo -e "discord debug mode on"
else
	DEB=0
	echo -e "debug mode off"
fi


# count errors and grab disk usage
tmp_disk_usage="$(df $MOUNTPOINT | grep / | awk '{ print $5}' | sed 's/%//g')%"
tmp_fatal_errors="$(docker logs --since 24h $NODENAME 2>&1 | grep 'FATAL' | grep -v -e 'INFO' -c)"
tmp_audits_failed="$(docker logs --since 24h $NODENAME 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep 'failed' -c)"
tmp_rest_of_errors="$(docker logs --since 24h $NODENAME 2>&1 | grep 'ERROR' | grep -v -e 'collector' -e 'piecestore' -e 'pieces error: filestore error: context canceled' -c)"


# select error messages in detail
DLOG=""
AUDS="$(docker logs --since 24h $NODENAME 2>&1 | grep -E 'GET_AUDIT|GET_REPAIR' | grep 'failed')"
FATS="$(docker logs --since 24h $NODENAME 2>&1 | grep 'FATAL' | grep -v 'INFO')"
ERRS="$(docker logs --since 24h $NODENAME 2>&1 | grep 'ERROR' | grep -v -e 'collector' -e 'piecestore' -e 'pieces error: filestore error: context canceled')"



# concatenate status message
if [[ $tmp_fatal_errors -eq 0 ]] && [[ $tmp_rest_of_errors -eq 0 ]] && [[ $tmp_audits_failed -eq 0 ]]; then 
	DLOG="**health check :** hdd $tmp_disk_usage; "
else
	DLOG="**warning :** "
fi

if [[ $tmp_fatal_errors -eq 0 ]] && [[ $tmp_rest_of_errors -eq 0 ]]; then 
	DLOG="$DLOG errors ok; "
elif [[ $tmp_fatal_errors -eq 0 ]]; then
	DLOG="$DLOG **ERRORS FOUND** ($tmp_rest_of_errors); "
elif [[ $tmp_rest_of_errors -eq 0 ]]; then
	DLOG="$DLOG **FATAL ERRORS** ($tmp_fatal_errors); "
else
    DLOG="$DLOG **FATAL /+ ERRORS** ($tmp_fatal_errors/$tmp_rest_of_errors); "
fi

if [[ $tmp_audits_failed -eq 0 ]]; then
	DLOG="$DLOG audit ok"
else
	DLOG="$DLOG **AUDIT ERRORS** ($tmp_audits_failed; recoverable: $audit_recfailrate; critical: $audit_failrate)"
fi


# dlog echo to terminal
echo "==="
echo "$DLOG"


# in case of audit issues, select and share details (recoverable or critical)

#count of successful audits
audit_success=$($LOG 2>&1 | grep GET_AUDIT | grep downloaded -c)
#count of recoverable failed audits
audit_failed_warn=$($LOG 2>&1 | grep GET_AUDIT | grep failed | grep -v exist -c)
audit_failed_warn_text=$($LOG 2>&1 | grep GET_AUDIT | grep failed | grep -v exist)
#count of unrecoverable failed audits
audit_failed_crit=$($LOG 2>&1 | grep GET_AUDIT | grep failed | grep exist -c)
audit_failed_crit_text=$($LOG 2>&1 | grep GET_AUDIT | grep failed | grep exist)
if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
then
	audit_recfailrate=$(printf '%.3f\n' $(echo -e "$audit_failed_warn $audit_success $audit_failed_crit" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	audit_recfailrate=0.000%
fi
if [ $(($audit_success+$audit_failed_crit+$audit_failed_warn)) -ge 1 ]
then
	audit_failrate=$(printf '%.3f\n' $(echo -e "$audit_failed_crit $audit_failed_warn $audit_success" | awk '{print ( $1 / ( $1 + $2 + $3 )) * 100 }'))%
else
	audit_failrate=0.000%
fi


# send discord ping
if [[ $tmp_fatal_errors -ne 0 ]] || [[ $tmp_rest_of_errors -ne 0 ]] || [[ $tmp_audits_failed -ne 0 ]] || [[ $DEB -eq 1 ]]; then 
        ./discord.sh --webhook-url="$URL" --username "storj stats" --text "$DLOG"
        echo ".. discord push sent."
fi


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


# send email alerts
if [[ $tmp_fatal_errors -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : FATAL ERRORS FOUND" --body "$FATS $MAILEOF" --silent "1"
	echo ".. fatal error mail sent."
fi
if [[ $tmp_rest_of_errors -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : OTHER ERRORS FOUND" --body "$ERRS $MAILEOF" --silent "1"
	echo ".. general error mail sent."
fi
if [[ $tmp_audits_failed -ne 0 ]]; then 
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : AUDIT ERRORS FOUND" --body "Recoverable: $audit_recfailrate \n\n$audit_failed_warn_text \n\nCritical: $audit_failrate \n\n$audit_failed_crit_text\n\nComplete: \n$AUDS \n\n$AUDS \n\n$MAILEOF" --silent "1"
	echo ".. audit error mail sent."
fi
# send debug mail 
if [[ $DEB -eq 2 ]]; then
	swaks --from "$MAILFROM" --to "$MAILTO" --server "$MAILSERVER" --auth LOGIN --auth-user "$MAILUSER" --auth-password "$MAILPASS" --h-Subject "STORAGENODE : DEBUG TEST MAIL" --body "blobb." --silent "1"
	echo ".. debut mail sent."
fi
