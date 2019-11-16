#!/bin/sh
#
: ' 
Created by René (https://github.com/rfuehrer)

Licensed to the Apache Software Foundation (ASF) under one
or more contributor license agreements.  See the NOTICE file
distributed with this work for additional information
regarding copyright ownership.  The ASF licenses this file
to you under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License.  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied.  See the License for the
specific language governing permissions and limitations
under the License.
'

THISDIR=$(dirname $0)
THISDIR=$(dirname $(realpath $0))
PARAMS=$1

# ------- DO NOT EDIT BEFORE THIS LINE -------
# VARIABLES TO EDIT
# CHECKHOSTS: network devices (eg. router or PC) as reference (name or IP) seperated with space
# WAITTIME_SHUTDOWN_SEC (in seconds): time between first and safty ping (for PC: use min. reboot time) to prevent shutdown while rebooting
# SLEEP_TIMER (in seconds): time between regular pings
# SLEEP_MAXLOOP: max loops to wait before shutdown (SLEEP_TIMER * SLEEP_MAXLOOP seconds)
# LOGFILE: name of the logfile
# LOGFILE_MAXLINES: max line number to keep in log file
#CHECKHOSTS="192.168.0.2 192.168.0.4 192.168.0.14"

# ########################################################
# ########################################################
# # DEFAULT VARIABLES
# ########################################################
# ########################################################
APP_VERSION="1.81"
APP_DATE="14.11.2019"
APP_SOURCE="https://github.com/rfuehrer/syno_autoshutdown/"

SLEEP_TIMER=10
SLEEP_MAXLOOP=180
GRACE_TIMER=4
LOGFILE_MAXLINES=100000
LOGFILE_CLEANUP_DAYS=7
DEBUG_MODE=0
RUNLOOP_COUNTER=0
MAXLOOP_COUNTER=0

CONFIGFILE=autoshutdown.config
HASHFILE=autoshutdown.hash
HASHSCRIPTFILE=autoshutdown.pidhash

# ------- DO NOT EDIT BELOW THIS LINE -------
# ########################################################
# ########################################################
# # GENERATED VARIABLES
# ########################################################
# ########################################################
PID=$BASHPID
LOG_TIMESTAMP_FORMAT=$(date +%Y%m%d_%H%M%S)
LOGFILE=autoshutdown_$LOG_TIMESTAMP_FORMAT.log
MY_PRIMARY_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
MY_SCAN_RANGE=$(echo $MY_PRIMARY_IP | cut -d. -f-3)
MY_START_TIME=$(date +"%d.%m.%Y %H:%M:%S")
MY_HOSTNAME=$(hostname)
SCRIPTFILE=$(basename "$0")
TEMPDIR=$THISDIR
if [ "z$MY_HOSTNAME" != "z" ]; then
    CONFIGFILE="autoshutdown-$MY_HOSTNAME.config"
	if [ ! -f "$THISDIR/$CONFIGFILE" ]; then
		# fallback config (generic)
    	CONFIGFILE="autoshutdown.config"
	fi
fi
SCRIPTFILE=$THISDIR/$SCRIPTFILE
LOGFILE=$THISDIR/$LOGFILE
CONFIGFILE=$THISDIR/$CONFIGFILE
HASHFILE=$THISDIR/$HASHFILE

# ########################################################
# ########################################################
# # FUNCTIONS
# ########################################################
# ########################################################

# -------------------------------------------
#######################################
# Resolve hostname from IP address
# Globals:
#   -
# Arguments:
#   $1: IP address
# Returns:
#   hostname
#######################################
get_hostname_from_ip(){
	local RET=$(arp -a|grep $1|awk '{print $1}'|cut -d. -f1)
	echo "$RET"
}

#######################################
# Convert string to lower case
# Globals:
#   -
# Arguments:
#   $1: string to be converted
# Returns:
#   lower case converted string
#######################################
string_to_lower(){
	local RET=$(echo "$1" | tr '[:upper:]' '[:lower:]')
	echo $RET
}

#######################################
# Read config file an variables
# Globals:
#   $HASHFILE
#	$CONFIGFILE
# Arguments:
#   -
# Returns:
#   $CHECKHOSTS
#	$MYNAME
#	$ACTIVE_STATUS
#	$DEBUG_MODE
#	$SLEEP_TIME
#	$SLEEP_MAXLOOP
#	$GRACE_TIMER
#	$LOGFILE_MAXLINES
#	$LOGFILE_CLEANUP_DAYS
#	$IFTTT_KEY
#	$IFTTT_EVENT
#	$SHUTDOWN_BEEP
#	$SHUTDOWN_BEEP_COUNT
#	$GRACE_BEEP
#	$GRACE_BEEP_COUNT
#	$NOTIFY_ON_GRACE_START
#	$NOTIFY_ON_GRAVE_EVERY
#	$NOTIFY_ON_SHUTDOWN
#	$NOTIFY_ON_LONGRUN_EVERY
#	$NOTIFY_ON_STATUS_CHANGE
#	$MESSAGE_SLEEP
#	$MESSAGE_GRACE_START
#	$MESSAGE_GRACE_EVERY
#	$MESSAGE_LONGRUN
#	$MESSAGE_STATUS_CHANGE_VAL
#	$MESSAGE_STATUS_CHANGE_INV
#######################################
read_config() {
  local MD5_HASH_SAVED=$(cat $HASHFILE)
  local MD5_HASH_CONFIG=$(md5sum $CONFIGFILE| cut -d ' ' -f 1)
  
  writelog "D" "Config hash : $MY_HOSTNAME : $CONFIGFILE"
  writelog "D" "Config hash - actual hash value: $MD5_HASH_CONFIG"
  writelog "D" "Config hash - saved hash value : $MD5_HASH_SAVED"

  if [ "$MD5_HASH_SAVED" != "$MD5_HASH_CONFIG" ]; then
    writelog "W" "Config hash - config modified, reload config"

    # save new hash value
    echo $MD5_HASH_CONFIG > $HASHFILE

    # reload config
    writelog "I" "(Re-)Reading config file..."
  	CHECKHOSTS=$(cat $CONFIGFILE | grep "^CHECKHOSTS" | cut -d= -f2)
	CHECKHOSTS="$CHECKHOSTS "
	CHECKHOSTS=$(string_to_lower "$CHECKHOSTS")
    writelog "I" "Set CHECKHOSTS to value $CHECKHOSTS"
  	
	MYNAME=$(cat $CONFIGFILE | grep "^MYNAME" | cut -d= -f2)
    writelog "I" "Set MYNAME to value $MYNAME"
  	
	ACTIVE_STATUS=$(cat $CONFIGFILE | grep "^ACTIVE_STATUS" | cut -d= -f2)
	# set default value, if not set by config
	: "${ACTIVE_STATUS:=1}"
    writelog "I" "Set ACTIVE_STATUS to value $ACTIVE_STATUS"

	DEBUG_MODE=$(cat $CONFIGFILE | grep "^DEBUG_MODE" | cut -d= -f2)
	# set default value, if not set by config
	: "${DEBUG_MODE:=0}"
    writelog "I" "Set DEBUG_MODE to value $DEBUG_MODE"

	SLEEP_TIMER=$(cat $CONFIGFILE | grep "^SLEEP_TIMER" | cut -d= -f2)
	# set default value, if not set by config
	: "${SLEEP_TIMER:=60}"
    writelog "I" "Set SLEEP_TIMER to value $SLEEP_TIMER"
    
	SLEEP_MAXLOOP=$(cat $CONFIGFILE | grep "^SLEEP_MAXLOOP" | cut -d= -f2)
	# set default value, if not set by config
	: "${SLEEP_MAXLOOP:=30}"
    writelog "I" "Set SLEEP_MAXLOOP to value $SLEEP_MAXLOOP"
    
	GRACE_TIMER=$(cat $CONFIGFILE | grep "^GRACE_TIMER" | cut -d= -f2)
	# set default value, if not set by config
	: "${GRACE_TIMER:=20}"
    writelog "I" "Set GRACE_TIMER to value $GRACE_TIMER"
    
	LOGFILE_MAXLINES=$(cat $CONFIGFILE | grep "^LOGFILE_MAXLINES" | cut -d= -f2)
	# set default value, if not set by config
	: "${LOGFILE_MAXLINES:=1000}"
    writelog "I" "Set LOGFILE_MAXLINES to value $LOGFILE_MAXLINES"

	LOGFILE_CLEANUP_DAYS=$(cat $CONFIGFILE | grep "^LOGFILE_CLEANUP_DAYS" | cut -d= -f2)
	# set default value, if not set by config
	: "${LOGFILE_CLEANUP_DAYS:=7}"
    writelog "I" "Set LOGFILE_CLEANUP_DAYS to value $LOGFILE_CLEANUP_DAYS"

	IFTTT_KEY=$(cat $CONFIGFILE | grep "^IFTTT_KEY" | cut -d= -f2)
    writelog "I" "Set IFTTT_KEY to magic value"

	IFTTT_EVENT=$(cat $CONFIGFILE | grep "^IFTTT_EVENT" | cut -d= -f2)
    writelog "I" "Set IFTTT_EVENT to value $IFTTT_EVENT"

    SHUTDOWN_BEEP=$(cat $CONFIGFILE | grep "^SHUTDOWN_BEEP" | cut -d= -f2)
	# set default value, if not set by config
	: "${SHUTDOWN_BEEP:=1}"

    SHUTDOWN_BEEP_COUNT=$(cat $CONFIGFILE | grep "^SHUTDOWN_BEEP_COUNT" | cut -d= -f2)
	# set default value, if not set by config
	: "${SHUTDOWN_BEEP_COUNT:=5}"

    GRACE_BEEP=$(cat $CONFIGFILE | grep "^GRACE_BEEP" | cut -d= -f2)
	# set default value, if not set by config
	: "${GRACE_BEEP:=1}"

    GRACE_BEEP_COUNT=$(cat $CONFIGFILE | grep "^GRACE_BEEP_COUNT" | cut -d= -f2)
	# set default value, if not set by config
	: "${GRACE_BEEP_COUNT:=1}"

	NOTIFY_ON_GRACE_START=$(cat $CONFIGFILE | grep "^NOTIFY_ON_GRACE_START" | cut -d= -f2)
	# set default value, if not set by config
	: "${NOTIFY_ON_GRACE_START:=1}"

	NOTIFY_ON_GRACE_EVERY=$(cat $CONFIGFILE | grep "^NOTIFY_ON_GRACE_EVERY" | cut -d= -f2)
	# set default value, if not set by config
	: "${NOTIFY_ON_GRACE_EVERY:=5}"

	NOTIFY_ON_SHUTDOWN=$(cat $CONFIGFILE | grep "^NOTIFY_ON_SHUTDOWN" | cut -d= -f2)
	# set default value, if not set by config
	: "${NOTIFY_ON_SHUTDOWN:=1}"

	NOTIFY_ON_LONGRUN_EVERY=$(cat $CONFIGFILE | grep "^NOTIFY_ON_LONGRUN_EVERY" | cut -d= -f2)
	# set default value, if not set by config
	: "${NOTIFY_ON_LONGRUN_EVERY:=180}"

	NOTIFY_ON_STATUS_CHANGE=$(cat $CONFIGFILE | grep "^NOTIFY_ON_STATUS_CHANGE" | cut -d= -f2)
	# set default value, if not set by config
	: "${NOTIFY_ON_STATUS_CHANGE:=1}"

    MESSAGE_SLEEP=$(cat $CONFIGFILE | grep "^MESSAGE_SLEEP" | cut -d= -f2)
	# set default value, if not set by config
	: "${MESSAGE_SLEEP:=System will be shut down now...}"

    MESSAGE_GRACE_START=$(cat $CONFIGFILE | grep "^MESSAGE_GRACE_START" | cut -d= -f2)
	# set default value, if not set by config
	: "${MESSAGE_GRACE_START:=System will be shut down soon...}"

    MESSAGE_GRACE_EVERY=$(cat $CONFIGFILE | grep "^MESSAGE_GRACE_EVERY" | cut -d= -f2)
	# set default value, if not set by config
	: "${MESSAGE_GRACE_EVERY:=System will be shut down soon...}"

	MESSAGE_LONGRUN=$(cat $CONFIGFILE | grep "^MESSAGE_LONGRUN" | cut -d= -f2)
	# set default value, if not set by config
	: "${MESSAGE_LONGRUN:=System is running for a long time...}"

	MESSAGE_STATUS_CHANGE_VAL=$(cat $CONFIGFILE | grep "^MESSAGE_STATUS_CHANGE_VAL" | cut -d= -f2)
	# set default value, if not set by config
	: "${MESSAGE_STATUS_CHANGE_VAL:=Systems found, starting normal mode...}"

	MESSAGE_STATUS_CHANGE_INV=$(cat $CONFIGFILE | grep "^MESSAGE_STATUS_CHANGE_INV" | cut -d= -f2)
	# set default value, if not set by config
	: "${MESSAGE_STATUS_CHANGE_INV:=No systems found, starting monitoring mode...}"

  else
	    writelog "I" "Config hash - hash value confirmed. No action needed."
  fi
}

#######################################
# Check hash value of pidfile
# Globals:
#   $SCRIPTFILE
#	$HASHSCRIPTFILE
#	$MD5_HASHSCRIPT_SAVED
# Arguments:
#   -
# Returns:
#   $MD5_HASHSCRIPT_SAVED
#######################################
check_pidhash(){
    local MD5_HASHSCRIPT=$(md5sum $SCRIPTFILE| cut -d ' ' -f 1)

    # first run?
    if [ ! -f $HASHSCRIPTFILE ]; then
        writelog "I" "Script hash - init new hash"
        echo $MD5_HASHSCRIPT > $HASHSCRIPTFILE
    fi

    MD5_HASHSCRIPT_SAVED=$(cat $HASHSCRIPTFILE)
    writelog "D" "Script hash : $SCRIPTFILE"
    writelog "D" "Script hash - actual hash value: $MD5_HASHSCRIPT"
    writelog "D" "Script hash - saved hash value : $MD5_HASHSCRIPT_SAVED"

    if [ "$MD5_HASHSCRIPT_SAVED" != "$MD5_HASHSCRIPT" ]; then
        # do something
        writelog "W" "Script hash - script modified, restart script"
        rm $HASHSCRIPTFILE
        $0 "$@" &
        exit 0
    else
        writelog "I" "Script hash - hash value confirmed. No action needed."
    fi
}

#######################################
# Beeps via system speaker of NAS
# Globals:
#   -
# Arguments:
#   $1: number of beeps
# Returns:
#   -
#######################################
beeps() {
	local BEEPS_NUM=$1
	
	for i in {1..$BEEPS_NUM}
	do
		writelog "I" "Beep."
		echo 2 > /dev/ttyS1
		sleep 1
	done
}

#######################################
# Replace placeholders in message strings
# Globals:
#   $VALID_MARKER_SYSTEMS_LIST
#	$MY_START_TIME
#	$MY_HOSTNAME
#	$MY_PRIMARY_IP
#	$RUNLOOP_COUNTER
#	$RUNLOOP_TIME
# Arguments:
#   $1: string to be converted
# Returns:
#   converted string
#######################################
replace_placeholder()
{
	local retvar="$1"

	# replace placeholders with variable content
	retvar=${retvar//#VALID_MARKER_SYSTEMS_LIST#/$VALID_MARKER_SYSTEMS_LIST}
	retvar=${retvar//#MY_START_TIME#/$MY_START_TIME}
	retvar=${retvar//#MY_HOSTNAME#/$MY_HOSTNAME}
	retvar=${retvar//#MY_PRIMARY_IP#/$MY_PRIMARY_IP}
	retvar=${retvar//#RUNLOOP_COUNTER#/$RUNLOOP_COUNTER}

	# note: loops * sleep_time
	local RUNLOOP_TIME=$((RUNLOOP_COUNTER*SLEEP_TIMER))
	retvar=${retvar//#RUNLOOP_TIME#/$RUNLOOP_TIME}
	local RUNLOOP_TIME_SECS=$((RUNLOOP_TIME))
	local RUNLOOP_TIME_DAYS=$((RUNLOOP_TIME_SECS/60/60/24))
    local RUNLOOP_TIME_HOURS=$((RUNLOOP_TIME_SECS/60/60%24))
    local RUNLOOP_TIME_MINS=$((RUNLOOP_TIME_SECS/60%60))
    local RUNLOOP_TIME_SECS=$((RUNLOOP_TIME_SECS%60))
	retvar=${retvar//#RUNLOOP_TIME_HUMAN#/${RUNLOOP_TIME_DAYS}d:${RUNLOOP_TIME_HOURS}h:${RUNLOOP_TIME_MINS}m:${RUNLOOP_TIME_SECS}s}

	local SYS_UPTIME_HUMAN=$(awk '{print int($1/3600)"h:"int(($1%3600)/60)"m:"int($1%60)"s"}' /proc/uptime)
	retvar=${retvar//#SYS_UPTIME_HUMAN#/$SYS_UPTIME_HUMAN}

	echo "$retvar"
}

#######################################
# Write message to STDOUT and log file
# Globals:
#   $DEBUG_MODE
#	$LOGFILE
#	$LOGFILE_MAXLINES
#	$PID
# Arguments:
#   $1: message level (I, D, W, E)
#	$2: message
# Returns:
#   -
#######################################
writelog()
{
	local NOW=$(date +"%d.%m.%Y %H:%M:%S")
	local MSGLEVEL=$1
	local MSG=$2

	# only output if NOT a "D" message or in debug mode
	if [ $MSGLEVEL != "D" ] || [ $DEBUG_MODE -eq 1 ]; then
		echo $NOW [$PID] [$MSGLEVEL] - $MSG
		echo $NOW [$PID] [$MSGLEVEL] - $MSG >>$LOGFILE
	fi

	# shorten logfile to max line number if not set to zero (0)
	if [ $LOGFILE_MAXLINES -ne 0 ]; then
		# log rotate
		COUNT_LINES=$(wc -l < "$LOGFILE")
		tail -n $LOGFILE_MAXLINES $LOGFILE >$LOGFILE.temp
		rm $LOGFILE
		mv $LOGFILE.temp $LOGFILE
	fi
}

#######################################
# Send notification to IFTTT
# Globals:
#   $IFTTT_KEY
#	$IFTTT_EVENT
# Arguments:
#   $1: Identifier / Host name
#	$2: Message
# Returns:
#   -
#######################################
notification()
{
	local MY_IDENTIFIER=$1
	local MY_MESSAGE=$2

	if [ "x$IFTTT_KEY" != "x" ]; then
		if [ "x$IFTTT_EVENT" != "x" ]; then
			if [ "x$MY_IDENTIFIER" != "x" ]; then
				writelog "D" "Notification NAME  : $MY_IDENTIFIER"
				writelog "D" "Notification STATUS:$MY_MESSAGE"
				writelog "D" "Notification EVENT :$IFTTT_EVENT"
				writelog "D" "Notification KEY   : $IFTTT_KEY"
				writelog "D" "{\"value1\":\"$MY_IDENTIFIER - $MY_MESSAGE\"} https://maker.ifttt.com/trigger/$IFTTT_EVENT/with/key/$IFTTT_KEY"
				curl -X POST -H "Content-Type: application/json" -d "{\"value1\":\"$MY_IDENTIFIER - $MY_MESSAGE\"}" https://maker.ifttt.com/trigger/$IFTTT_EVENT/with/key/$IFTTT_KEY
			else
				writelog "E" "No notification message stated. Notification aborted."
			fi
		else
			writelog "E" "No notification event name stated. Notification aborted."
		fi
	else
		writelog "E" "No notification magic key stated. Notification aborted."
	fi
}

# ########################################################
# ########################################################
# # MAIN PROGRAM
# ########################################################
# ########################################################

#if pidof -o %PPID -x $SCRIPTFILE>/dev/null; then
#	echo "Process already running"
#fi

# ########################################################
# # INTRO HEADER
writelog "W" "################################################################################"
writelog "I" "#####"
writelog "W" "##### autoshutdown.sh  for Synology-NAS"
writelog "I" "#####"
writelog "I" "##### Version $APP_VERSION, $APP_DATE"
writelog "I" "##### $APP_SOURCE"
writelog "I" "##### Licensed under APLv2"
writelog "I" "#####"
writelog "W" "################################################################################"
writelog "I" "base directory: $THISDIR"
writelog "I" "own primary ip: $MY_PRIMARY_IP"
writelog "I" "scan ip range : $MY_SCAN_RANGE.*"

writelog "I" "Removing old (7 days) logs"
DUMMY=$(find $THISDIR/ -type f -mtime +$LOGFILE_CLEANUP_DAYS -name 'autoshutdown_*.log' -exec rm {} \;)

# ########################################################
# # COMMANDLINE PARAMETER
OPT_RESETLOG=0
OPT_VERBOSE=0
OPT_KILLALL=0
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--verbose)
            case "$2" in
                "") ARG_A='some default value' ; shift 2 ;;
                *) ARG_A=$2 ; shift 2 ;;
            esac ;;
        -v|--verbose) OPT_VERBOSE=1 ; shift ;;
        -k|--killall) OPT_KILLALL=1 ; shift ;;
		-r|--resetlog) OPT_RESETLOG = 1; shift;;
        --) shift ; break ;;
        *) break ;;
    esac
done

if [ $OPT_KILLALL -eq 1 ]; then
	writelog "I" "Terminating myself because of manual kill switch"
	echo "Terminating myself because of manual kill switch"

	pkill "autoshutdown"
# if pkill not working
#	ps aux|grep "autoshutdown.sh"|awk '{print $2}'|sudo xargs kill -9
	exit 0
fi

# resetlog: resets the log only at start to get en empty log. other options are still valid
if [ $OPT_RESETLOG -eq 1 ]; then
	rm $LOGFILE
	OPT_RESETLOG = 0
fi

# ########################################################
# # MAIN LOOP
# cleanup hash file (create new configfile)
rm $HASHFILE
# main loop
while true; do
	if [ ! -f "$CONFIGFILE" ]; then
		# no config file found; check every loop to get sure, the function is executable
		writelog "I" ""
		writelog "I" "NO VALID CONFIG FILE FOUND - ABORT!"
		writelog "I" ""
		exit 0
	else
	    read_config
	fi
    check_pidhash

	FOUND_SYSTEMS=0
	VALID_MARKER_SYSTEMS_LIST=""
	RUNLOOP_COUNTER=$((RUNLOOP_COUNTER+1))
	RUNLOOP_MOD=$((RUNLOOP_COUNTER % NOTIFY_ON_LONGRUN_EVERY))

	if [ $RUNLOOP_MOD -eq 0 ];then
		writelog "I" "Sending notification (MESSAGE_LONGRUN)"

		MESSAGE_LONGRUN_NOTIFY=$(replace_placeholder "$MESSAGE_LONGRUN")
		notification "$MYNAME" "$MESSAGE_LONGRUN_NOTIFY"
		writelog "I" "Notification sent: $MESSAGE_LONGRUN_NOTIFY"
	fi

	if [ $ACTIVE_STATUS != "1" ]; then
		writelog "I" "Autoshutdown (temporary?) disabled. Waiting for next check in $SLEEP_TIMER seconds..."
	else
		writelog "I" "Checking systems (loop $MAXLOOP_COUNTER of $SLEEP_MAXLOOP; $SLEEP_TIMER seconds waiting time)"

		# get all online IP addresses
		FOUND_HOSTS=$(for i in {1..254} ;do (ping $MY_SCAN_RANGE.$i -c 1 -w 5  >/dev/null && echo "$MY_SCAN_RANGE.$i" &) ;done)
		# search local network
		for FOUND_IP in $FOUND_HOSTS
		do
			# match marker systems with online systems (IP based)
			# note: space is important to find this IP (CHECKHOSTS has an additional space at end)
			if grep -q "$FOUND_IP " <<< "$CHECKHOSTS"; then
					DUMMY="System (IP)"
					VALID_MARKER_SYSTEMS_LIST="$VALID_MARKER_SYSTEMS_LIST$FOUND_IP "
					FOUND_SYS=$(get_hostname_from_ip $FOUND_IP)
					DUMMY="$DUMMY [$FOUND_IP -> $FOUND_SYS] - valid marker system"
					FOUND_SYSTEMS=$((FOUND_SYSTEMS+1))
					writelog "I" "$DUMMY"
			else
				# match marker systems with online systems (IP translated in hostname)
				FOUND_SYS=$(nslookup $FOUND_IP | awk '/name/ {split ($4,elems,"."); print elems[1]}')
				FOUND_SYS=$(string_to_lower "$FOUND_SYS")
				writelog "D" "FOUND_SYS (lower)=$FOUND_SYS"
				# find multi hostname systems (e.g. fritzbox)
				FOUND_SYS_LINES=$(nslookup $FOUND_IP | awk '/name/ {split ($4,elems,"."); print elems[1]}'| wc -l)
				# check valid ip address (vs. multiple hostnames)
				if [[ $FOUND_SYS_LINES -eq 1 ]]; then
						# only accept ssingle-line matches (unique hostnames)
					if [ ! -z $FOUND_SYS ]; then
						CHECKHOSTS=$(echo $CHECKHOSTS | tr '[A-Z]' '[a-z]')
						FOUND_SYS=$(echo $FOUND_SYS | tr '[A-Z]' '[a-z]')
						DUMMY="System '$FOUND_SYS' "
						if grep -q "$FOUND_SYS" <<< "$CHECKHOSTS" ; then
							VALID_MARKER_SYSTEMS_LIST="$VALID_MARKER_SYSTEMS_LIST$FOUND_SYS "
							DUMMY="$DUMMY [$FOUND_IP] - valid marker system"
							FOUND_SYSTEMS=$((FOUND_SYSTEMS+1))
						else
							DUMMY="$DUMMY - not decisive"
						fi
						writelog "I" "$DUMMY"
					fi
				else
					writelog "I" "multiple hostname system [$FOUND_IP] - ignore"
				fi
			fi
		done

		writelog "D" "FOUND_SYSTEMS=$FOUND_SYSTEMS"
		writelog "D" "MAXLOOP_COUNTER=$MAXLOOP_COUNTER"
		writelog "D" "RUNLOOP_COUNTER=$RUNLOOP_COUNTER"
		writelog "D" "NOTIFY_ON_STATUS_CHANGE=$NOTIFY_ON_STATUS_CHANGE"
		# if variable couldn't be resetted
		if [ $FOUND_SYSTEMS -ge 1 ]; then
			# now systems found
			# note: former status is no system found (resetted loop counter)?
			if [ $MAXLOOP_COUNTER -ne 0 ]; then
				if [ $RUNLOOP_COUNTER -gt 1 ]; then
				writelog "I" "--> status change (not found -> found)"
					# only send notification after first loop
					if [ $NOTIFY_ON_STATUS_CHANGE -eq "1" ];then
						writelog "I" "Sending notification (MESSAGE_STATUS_CHANGE_VAL)"
						notification "$MYNAME" "$MESSAGE_STATUS_CHANGE_VAL"
						writelog "I" "Notification sent: $MESSAGE_STATUS_CHANGE_VAL"
					fi
				fi
			fi
			# reset counter
			MAXLOOP_COUNTER=0
			writelog "W" "$FOUND_SYSTEMS marker systems found. Resetting loop."
			### Trim whitespaces ###
			VALID_MARKER_SYSTEMS_LIST=$(echo $VALID_MARKER_SYSTEMS_LIST | sed -e 's/^[[:space:]]*//')
			# replace spaces with ", "
			VALID_MARKER_SYSTEMS_LIST=${VALID_MARKER_SYSTEMS_LIST// /, }

			RETURN_VAR=$(replace_placeholder "Found system names: #VALID_MARKER_SYSTEMS_LIST#")
			writelog "I" "$RETURN_VAR"
		else
			# now no systems found
			# note: former status is system found (incremented loop counter)
			if [ $MAXLOOP_COUNTER -eq 0 ]; then
				# status change detected?
				writelog "I" "--> status change (found -> not found)"
				if [ $RUNLOOP_COUNTER -gt 1 ]; then
					# only send notification after first loop
					if [ $NOTIFY_ON_STATUS_CHANGE -eq "1" ];then
						writelog "I" "Sending notification (MESSAGE_STATUS_CHANGE_INV)"
						notification "$MYNAME" "$MESSAGE_STATUS_CHANGE_INV"
						writelog "I" "Notification sent: $MESSAGE_STATUS_CHANGE_INV"
					fi
				fi
			fi
			# increment counter
			MAXLOOP_COUNTER=$((MAXLOOP_COUNTER+1))
			writelog "W" "No marker systems found. Proceeding with loop. ($MAXLOOP_COUNTER of $SLEEP_MAXLOOP)"
		fi

		# counter > grace timer?
		if [ $MAXLOOP_COUNTER -ge $GRACE_TIMER ];then
			# counter = grace timer?
			if [ $MAXLOOP_COUNTER -eq $GRACE_TIMER ];then
				# send notification
				if [ $NOTIFY_ON_GRACE_START -eq "1" ];then
					writelog "I" "Sending notification (NOTIFY_ON_GRACE_START)"
					MESSAGE_GRACE_START_NOTIFY=$(replace_placeholder "$MESSAGE_GRACE_START")
					notification "$MYNAME" "$MESSAGE_GRACE_START_NOTIFY"
					writelog "I" "Notification sent: $MESSAGE_GRACE_START_NOTIFY"
				fi
			else
				# send notification on every ... ?
				if [ $NOTIFY_ON_GRACE_EVERY -eq "1" ];then
					writelog "I" "Sending notification (NOTIFY_ON_GRACE_EVERY)"
					MESSAGE_GRACE_EVERY_NOTIFY=$(replace_placeholder "$MESSAGE_GRACE_EVERY")
					notification "$MYNAME" "$MESSAGE_GRACE_EVERY_NOTIFY"
					writelog "I" "Notification sent: $MESSAGE_GRACE_EVERY_NOTIFY"
				fi
			fi
			
			# beep on every loop in grace period?
			if [ $GRACE_BEEP == "1" ];then
				beeps $GRACE_BEEP_COUNT
			fi
		fi
		# summary
		RUNLOOP_COUNTER_TIME=$((RUNLOOP_COUNTER*SLEEP_TIMER))

		writelog "I" "#####################################################"
		writelog "I" "#####                                                "
		writelog "I" "#####        S H U T D O W N  C O U N T E R          "
		writelog "I" "#####                                                "
		writelog "I" "#####                   checks: $RUNLOOP_COUNTER = $RUNLOOP_COUNTER_TIME sec."
		writelog "I" "#####                   modula: $RUNLOOP_MOD / $NOTIFY_ON_LONGRUN_EVERY"
		writelog "I" "#####                   loop: $MAXLOOP_COUNTER / max: $SLEEP_MAXLOOP"
		writelog "I" "#####                                                "
		writelog "I" "#####################################################"

		# check if loop > maxloop?
		if [ $MAXLOOP_COUNTER -ge $SLEEP_MAXLOOP ]; then
			# check if still no system found
			if [ $FOUND_SYSTEMS -eq 0 ]; then
				writelog "I" "STATUS: All systems still offline!"
				writelog "I" "Shutting down this system... Sleep well :)"
				# send notification on system shutdown?
				if [ $NOTIFY_ON_SHUTDOWN -eq "1" ];then
					MESSAGE_SLEEP=$(replace_placeholder "$MESSAGE_SLEEP")
					notification "$MYNAME" "$MESSAGE_SLEEP"
					writelog "I" "Notification sent: $MESSAGE_SLEEP"
				fi
				# beep on system shutdown?
				if [ $SHUTDOWN_BEEP == "1" ];then
					beeps $SHUTDOWN_BEEP_COUNT
				fi
				poweroff
				writelog "I" "#####################################################"
				writelog "I" "#####                 G O O D B Y                    "
				writelog "I" "#####################################################"
				sleep 60
				exit 0
			fi
		fi
		writelog "I" "Waiting for next check in $SLEEP_TIMER seconds..."
	fi
	
	# sleep till next loop
	sleep $SLEEP_TIMER

done;