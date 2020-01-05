#!/usr/bin/env bash
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

THISDIR=$(dirname "$0")
THISDIR=$(dirname "$(realpath "$0")")

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
APP_NAME="Syno Autoshutdown"
APP_VERSION="2.2"
APP_DATE="05.01.2020"
APP_SOURCE="https://github.com/rfuehrer/syno_autoshutdown/"

SLEEP_TIMER=10
SLEEP_MAXLOOP=180
GRACE_TIMER=4
LOGFILE_MAXLINES=100000
LOGFILE_CLEANUP_DAYS=7
DEBUG_MODE=0
RUNLOOP_COUNTER=0
MAXLOOP_COUNTER=0
DMSS_ACTIVE=0
DMSS_ACTIVE_COUNTER=0

CONFIGFILE=autoshutdown.config
CONFIGFILE_INI=autoshutdown.config.ini
HASHFILE=autoshutdown.config.hash
HASHSCRIPTFILE=autoshutdown.sh.pidhash
HASHSCRIPTFILE_DEV=autoshutdown.sh-dev.pidhash

# ------- DO NOT EDIT BELOW THIS LINE -------
# ########################################################
# ########################################################
# # GENERATED VARIABLES
# ########################################################
# ########################################################
PID=$BASHPID
LOG_TIMESTAMP_FORMAT_DATETIME=$(date +%Y%m%d_%H%M%S)
LOG_TIMESTAMP_FORMAT_DATE=$(date +%Y%m%d)
LOG_TIMESTAMP_FORMAT_TIME=$(date +%H%M%S)
MY_PRIMARY_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
MY_SCAN_RANGE=$(echo "$MY_PRIMARY_IP" | cut -d. -f-3)
MY_START_TIME=$(date +"%d.%m.%Y %H:%M:%S")
MY_HOSTNAME=$(hostname)
SCRIPTFILE=$(basename "$0")
if [ "z$MY_HOSTNAME" != "z" ]; then
    CONFIGFILE="autoshutdown-$MY_HOSTNAME.config"
	if [ ! -f "$THISDIR/$CONFIGFILE" ]; then
		# fallback config (generic)
    	CONFIGFILE="autoshutdown.config"
	fi
fi
SCRIPTFILE="$THISDIR/$SCRIPTFILE"
CONFIGFILE="$THISDIR/$CONFIGFILE"
HASHFILE="$THISDIR/$HASHFILE"

# reset color
COLOR_NC="\033[0m"

MY_PUBLIC_IP=$(curl --silent checkip.amazonaws.com 2>&1)
MY_UUID=$(uuidgen)
MY_WEBSERVER_MAGICKEY_GENERATED=$(uuidgen|md5sum|cut -d ' ' -f 1)

# ########################################################
# ########################################################
# # FUNCTIONS
# ########################################################
# ########################################################

# -------------------------------------------

#######################################
# Convert seconds to human readable format
# Globals:
#   -
# Arguments:
#   $1: seconds
#   $2: format (long/short)
# Returns:
#   
#######################################
sec_to_time() {
    local MY_SECONDS=$1
	local MY_FORMAT=${2:-short}
    local sign=""
	local hours
	local minutes
	local seconds
	local HRF_SECONDS
	
    if [[ ${MY_SECONDS:0:1} == "-" ]]; then
        seconds=${MY_SECONDS:1}
        sign="-"
    fi
    local days=$(( (MY_SECONDS / 3600) / 24))
    local hours=$(( (MY_SECONDS / 3600) ))
    local minutes=$(( (MY_SECONDS % 3600) / 60 ))
    seconds=$(( (MY_SECONDS) % 60 ))

	if [ "$MY_FORMAT" != "long" ]; then
    	HRF_SECONDS=$(printf "%s%02d:%02d:%02d:%02d" "$sign" $days $hours $minutes $seconds)
	else
    	HRF_SECONDS=$(printf "%s%02dd:%02dh:%02dm:%02ds" "$sign" $days $hours $minutes $seconds)
	fi
	writelog "D" "Conversion of seconds: $MY_SECONDS => $HRF_SECONDS"
	echo "$HRF_SECONDS"
}


check_hash_script_modified(){
    MD5_HASHSCRIPT_SAVED=$(cat $HASHSCRIPTFILE)
    if [ "$MD5_HASHSCRIPT_SAVED" != "$MD5_HASHSCRIPT" ]; then
		RET=1
    else
        RET=0
    fi
	echo $RET
}

#######################################
# Starts an asynchron webserver
# Globals:
#   -
# Arguments:
#   $1: port numbr
# Returns:
#   
#######################################
init_webserver_shutdown(){
	# check if script file is modified? if true, the webserver would be restarted after reloading/restarting the script
#	SCRIPT_MODIFIED=$(check_hash_script_modified)
#	if [ $SCRIPT_MODIFIED -eq 0 ]; then
	# shutdown all previous instances
	WEBSERVER_INSTANCES=$(ps -ef|grep -v grep|grep $WEBSERVER_SHUTDOWN_SCRIPT|wc -l)
	while [[ $WEBSERVER_INSTANCES -ne 0 ]]; do
		writelog "I" "Kill all instances ($WEBSERVER_INSTANCES) of '$WEBSERVER_SHUTDOWN_SCRIPT'"
		pkill -f "$WEBSERVER_SHUTDOWN_SCRIPT" >/dev/null 2>&1
		sleep 2
		WEBSERVER_INSTANCES=$(ps -ef|grep -v grep|grep -c "$WEBSERVER_SHUTDOWN_SCRIPT")
	done
	sleep 5

	WEBSERVER_INSTANCES=$(ps -ef|grep -v grep|grep -c "$WEBSERVER_SHUTDOWN_SCRIPT")
	WEBSERVER_STARTUP_FAILED=0
	WEBSERVER_STARTUP_COUNTER=0
	writelog "I" "Waiting for webserver to start (instances=$WEBSERVER_INSTANCES; loop=$WEBSERVER_STARTUP_COUNTER)"
	while [[ $WEBSERVER_STARTUP_FAILED -eq 0 ]] && [[ $WEBSERVER_INSTANCES -eq 0 ]]; do
		WEBSERVER_STARTUP_COUNTER=$((WEBSERVER_STARTUP_COUNTER+1))

		if [ "$WEBSERVER_INSTANCES" -eq 0 ]; then 
			PYTHON_EXEC=$(command -v python)
			"$PYTHON_EXEC" "$THISDIR/$WEBSERVER_SHUTDOWN_SCRIPT" --port "$WEBSERVER_SHUTDOWN_PORT" --uuid "$MY_UUID" --spath "$WEBSERVER_SHUTDOWN_URL" --tpath "$WEBSERVER_TEST_URL" --magickey "$WEBSERVER_MAGICKEY" --magicword "$WEBSERVER_MAGICWORD" --rpath "$WEBSERVER_DMSS_RESET_URL" &
		fi
		
		sleep 2
		WEBSERVER_INSTANCES=$(ps -ef|grep -v grep|grep -c "$WEBSERVER_SHUTDOWN_SCRIPT")
		writelog "I" "Waiting for webserver to start (instances=$WEBSERVER_INSTANCES; loop=$WEBSERVER_STARTUP_COUNTER)"

		if [ "$WEBSERVER_STARTUP_COUNTER" -gt 5 ]; then
			WEBSERVER_STARTUP_FAILED=1
		fi
	done

	if [ $WEBSERVER_INSTANCES -eq 0 ]; then
		writelog "W" "Failed to start webserver!"
	else
		writelog "I" "Shutdown webserver (external call) set to 'http://$MY_PUBLIC_IP:$WEBSERVER_SHUTDOWN_PORT_EXTERNAL/$MY_UUID/$WEBSERVER_SHUTDOWN_URL'"
		writelog "I" "Shutdown webserver (local call) set to 'http://localhost:$WEBSERVER_SHUTDOWN_PORT/$MY_UUID/$WEBSERVER_TEST_URL'"
		#notification "$MYNAME" "$MESSAGE_WEBSERVER_SHUTDOWN_START"
		#notification "$MYNAME" "http://$MY_PUBLIC_IP:$WEBSERVER_SHUTDOWN_PORT_EXTERNAL/$MY_UUID/$WEBSERVER_SHUTDOWN_URL"
	fi
#	else
#		writelog "I" "Script modified, do not start webserver in this instance... Please wait for reloading."
#	fi
}



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
	local RET
	RET=$(arp -a|grep "$1"|awk '{print $1}'|cut -d. -f1)
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
	local RET
	RET=$(echo "$1" | tr '[:upper:]' '[:lower:]')
	echo "$RET"
}


#######################################
# Read/Write value in config file
# Globals:
#   $CONFIGFILE
# Arguments:
#   $1: variable name
#	$2: default value
#	$3: description of variable
#	$4: output read value to console(log (0/1))
#	$5: initialize config value if not present (0/1) - a later call with <>0 will initialize missing values
# Returns:
#   -
#######################################
function ini_val() {
	# BASH3 Boilerplate: ini_val
	#
	# This file:
	#
	#  - Can read and write .ini files using pure bash
	#
	# Limitations:
	#
	#  - All keys inside the .ini file must be unique, regardless of the use of sections
	#
	# Usage as a function:
	#
	#  source ini_val.sh
	#  ini_val data.ini connection.host 127.0.0.1
	#
	# Usage as a command:
	#
	#  ini_val.sh data.ini connection.host 127.0.0.1
	#
	# Based on a template by BASH3 Boilerplate v2.4.1
	# http://bash3boilerplate.sh/#authors
	#
	# The MIT License (MIT)
	# Copyright (c) 2013 Kevin van Zonneveld and contributors
	# You are not obligated to bundle the LICENSE file with your b3bp projects as long
	# as you leave these references intact in the header comments of your source files.	


	# ini_val $CONFIGFILE $MY_VAR $MY_DEFAULT $MY_DESCRIPTION $MY_OUTPUT $MY_INIT_CONFIG

  local file="${1:-}"
  local sectionkey="${2:-}"
  local val="${3:-}"
  local comment="${4:-}"
  local delim="="
  local comment_delim=";"
  local section=""
  local key=""
  local current=""
  # add default section
  local section_default="default"

  if [[ ! -f "${file}" ]]; then
    # touch file if not exists
    touch "${file}"
  fi

  # Split on . for section. However, section is optional
  IFS='.' read -r section key <<< "${sectionkey}"
  if [[ ! "${key}" ]]; then
    key="${section}"
    # default section if not given
    section="${section_default}"
  fi

  current=$(sed -En "/^\[/{h;d;};G;s/^${key}([[:blank:]]*)${delim}(.*)\n\[${section}\]$/\2/p" "${file}"|awk '{$1=$1};1')

  if ! grep -q "\[${section}\]" "${file}"; then
    # create section if not exists (empty line to seperate new section)
    echo  >> "${file}"
    echo "[${section}]" >> "${file}"
  fi

  if [[ ! "${val}" ]]; then
    # get a value
    echo "${current}"
  else
    # set a value
    if [[ ! "${current}" ]]; then
      # doesn't exist yet, add
      if [[ ! "${section}" ]]; then
        # if no section is given, propagate the default section
        section=${section_default}
      fi
      # add to section
      if [[ ! "${comment}" ]]; then
        # add new key/value without description
        RET="/\\[${section}\\]/a\\
${key}${delim}${val}"
      else
        # add new key/value with description
        RET="/\\[${section}\\]/a\\
${comment_delim}[${key}] ${comment}\\
${key}${delim}${val}"
      fi
      sed -i.bak -e "${RET}" "${file}"
      # this .bak dance is done for BSD/GNU portability: http://stackoverflow.com/a/22084103/151666
      rm -f "${file}.bak"
    else
      # replace existing (modified to replace only keys in given section)
      sed -i.bak -e "/^\[${section}\]/,/^\[.*\]/ s|^\(${key}[ \t]*${delim}[ \t]*\).*$|\1${val}|" "${file}"
      # this .bak dance is done for BSD/GNU portability: http://stackoverflow.com/a/22084103/151666
      rm -f "${file}.bak"
    fi
  fi
}

#######################################
# Read/Init value in config file
# Globals:
#   $CONFIGFILE
# Arguments:
#   $1: variable name
#	$2: default value
#	$3: description of variable
#	$4: output read value to console(log (0/1))
#	$5: initialize config value if not present (0/1) - a later call with <>0 will initialize missing values
# Returns:
#   -
#######################################
read_config_value(){
	local MY_VAR=$1
	local MY_DEFAULT=$2
	local MY_DESCRIPTION=$3
	local MY_OUTPUT=$4
	local MY_INIT_CONFIG=$5
	
	local RET
	RET=""

	if grep -q "^$MY_VAR" "$CONFIGFILE"
	then
		# string found
		RET=$(cat "$CONFIGFILE" | grep "^$MY_VAR=" | cut -d= -f2)
#		: "${ACTIVE_STATUS:=1}"
		if [ "$RET" == "" ];then
			[ "$MY_OUTPUT" == "1" ] && writelog "I" "No config value '$MY_VAR' in config file. Setting default value '$MY_DEFAULT'."
			RET="$MY_DEFAULT"
		fi
	else
		RET=$MY_DEFAULT
		if [ "$MY_INIT_CONFIG" != "0" ]; then
			# string not found
			[ "$MY_OUTPUT" == "1" ] && writelog "I" "No variable '$MY_VAR' found in config file. Initializing variable to config file."
			echo "" >>"$CONFIGFILE"
			echo "; [$MY_VAR] $MY_DESCRIPTION" >>"$CONFIGFILE"
			echo "$MY_VAR=$MY_DEFAULT" >>"$CONFIGFILE"
		fi
	fi

	# set dynamic variable name to read content
	eval $MY_VAR=\$RET
	[ "$MY_OUTPUT" == "1" ] && writelog "I" "Set variable '$MY_VAR' to value '$RET'"
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
  local MD5_HASH_SAVED=$(cat "$HASHFILE")
  local MD5_HASH_CONFIG=$(md5sum "$CONFIGFILE"| cut -d ' ' -f 1)
  
  writelog "D" "Config hash : $MY_HOSTNAME : $CONFIGFILE"
  writelog "D" "Config hash - actual hash value: $MD5_HASH_CONFIG"
  writelog "D" "Config hash - saved hash value : $MD5_HASH_SAVED"

  if [ "$MD5_HASH_SAVED" != "$MD5_HASH_CONFIG" ]; then
    writelog "W" "Config hash - config modified, reload config"

    # save new hash value
    echo "$MD5_HASH_CONFIG" > "$HASHFILE"

	# reset DMSS vars to prevent execution of existing grace periods and changed config vars
	DMSS_ACTIVE=0
	DMSS_ACTIVE_COUNTER=0

    # reload config
    writelog "I" "(Re-)Reading config file..."
  	
	read_config_value "CHECKHOSTS" "add-systems-to-monitor seperate-with-spaces" "client (to be checked) information; separated by space (valaue: $)" 1 1
	CHECKHOSTS="$CHECKHOSTS "
	CHECKHOSTS=$(string_to_lower "$CHECKHOSTS")

	read_config_value "CHECKHOSTS_DEEPSLEEP" "add-systems-with-deep-sleep-mode" "client (to be checked) with deep sleep mode (special checks); separated by space (valaue: $)" 1 1
	CHECKHOSTS_DEEPSLEEP="$CHECKHOSTS_DEEPSLEEP "
	CHECKHOSTS_DEEPSLEEP=$(string_to_lower "$CHECKHOSTS_DEEPSLEEP")

	read_config_value "CHECKHOSTS_IGNORE_MULTI_HOSTNAMES" 1 "if set ignore all names except the first one (valaue: 0/1 [1])" 1 1

	read_config_value "MYNAME" "$MY_HOSTNAME" "cutsomizable hostname of executing NAS (used in notifications) (valaue: $)" 1 1
	read_config_value "ACTIVE_STATUS" 1 "active status of this script (for manual deactivation) (value: 0/1 [1])" 1 1
	read_config_value "DEBUG_MODE" 0 "debug mode (outut of debug messages to stdout and log) (value: 0/1 [0])" 1 1
	read_config_value "USE_INTERACTIVE_COLOR" 1 "use color codes in interactive/console mode (value: 0/1 [1])" 1 1

	# Color codes
	#Black        0;30     Dark Gray     1;30
	#Red          0;31     Light Red     1;31
	#Green        0;32     Light Green   1;32
	#Brown/Orange 0;33     Yellow        1;33
	#Blue         0;34     Light Blue    1;34
	#Purple       0;35     Light Purple  1;35
	#Cyan         0;36     Light Cyan    1;36
	#Light Gray   0;37     White         1;37
	read_config_value "COLOR_ERROR" "\033[0;31m" "color code for error classification (value: $)" 0 1
	read_config_value "COLOR_WARNING" "\033[0;33m" "color code for warning classification (value: $)" 0 1
	read_config_value "COLOR_INFO" "\033[1;37m" "color code for info classification (value: $)" 0 1
	read_config_value "COLOR_DEBUG" "\033[1;30m" "color code for debug classification (value: $)" 0 1
	read_config_value "COLOR_PID" "\033[0;35m" "color code for process id" 0 1

	read_config_value "SLEEP_TIMER" 60 "wating time (loop) to check clients again (value: # [60])" 1 1
	read_config_value "SLEEP_MAXLOOP" 30 "number of max loops (value: # [30])" 1 1
	read_config_value "GRACE_TIMER" 20 "start grace period after x loops (value: # [20])" 1 1

	read_config_value "LOGFILE_MAXLINES" 1000 "limit log file to number of lines (value: # [1000])" 1 1
	read_config_value "LOGFILE_CLEANUP_DAYS" 3 "clean log files older than x days (value: # [3])" 1 1
	read_config_value "LOGFILE_FILENAME" "autoshutdown.log" "define log filename; placeholder optionally (#DATETIME#) (value: $ [autoshutdown.log])" 1 1
	LOGFILE=$(replace_logfilename_placeholder "$LOGFILE_FILENAME")
	LOGFILE="$THISDIR/$LOGFILE"
	read_config_value "SCRIPT_DEV_FILENAME" "autoshutdown.sh.txt" "define script filename for edited version (copies from this file to running script at start of loop; prevents text file busy errors) (value: $)" 1 1
	SCRIPTFILE_DEV="$THISDIR/$SCRIPT_DEV_FILENAME"

	read_config_value "IFTTT_KEY" "" "IFTTT magic key for webhook notifications (value: $)" 0 1
	read_config_value "IFTTT_EVENT" "" "IFTTT event name for notifications (value: $)" 1 1

	read_config_value "SHUTDOWN_BEEP" 1 "beep system loudspeaker if shutting down (value: 0/1 [1])" 1 1
	read_config_value "SHUTDOWN_BEEP_COUNT" 5 "number of beeps at shutdown (value: # [5])" 1 1
 	read_config_value "GRACE_BEEP" 1 "beep system loudspeaker if in grace period (value: 0/1 [1])" 1 1
	read_config_value "GRACE_BEEP_COUNT" 1 "number of beeps in grace period (value: # [1])" 1 1

	read_config_value "NOTIFY_ON_GRACE_START" 1 "send notification on start of grace period (value: 0/1 [1])" 1 1
	read_config_value "NOTIFY_ON_GRACE_EVERY" 5 "send notification in grace period (value: # [5])" 1 1
	read_config_value "NOTIFY_ON_SHUTDOWN" 1 "send notification on shutdown (value: 0/1 [1])" 1 1
	read_config_value "NOTIFY_ON_LONGRUN_EVERY" 180 "send notification if system is running a long time (value: # [180])" 1 1
	read_config_value "NOTIFY_ON_STATUS_CHANGE" 1 "send notification if status of connected system changes (value: 0/1 [1])" 1 1

	read_config_value "DSM_NOTIFY_ON_STATUS_CHANGE" 1 "send Synology DSM notification if status of connected system changes (value: 0/1 [1])" 1 1


 	read_config_value "MESSAGE_SLEEP" "System will be shut down now..." "notification message if system is shutting down (valaue: $)" 1 1
 	read_config_value "MESSAGE_GRACE_START" "System will be shut down soon..." "notification message if grace periods starts (valaue: $)" 1 1
  	read_config_value "MESSAGE_GRACE_EVERY" "System will be shut down soon..." "notification message while in grace period (valaue: $)" 1 1
 	read_config_value "MESSAGE_LONGRUN" "System is running for a long time..." "notification message if system is running a long time (valaue: $)" 1 1
 	read_config_value "MESSAGE_STATUS_CHANGE_VAL" "Systems found, starting normal mode..." "notification message if valid systems are found (valaue: $)" 1 1
 	read_config_value "MESSAGE_STATUS_CHANGE_INV" "No systems found, starting monitoring mode..." "notification message if no valid systems are found (valaue: $)" 1 1
 	read_config_value "MESSAGE_LAST_SYSTEM_DEEPSLEEP" "Remaining valid system seems to be in deep sleep mode. Continuing checks.." "notification message if remaining system is possible in deep sleep mode (valaue: $)" 1 1
 
	read_config_value "NETWORK_USAGE_INTERFACE" "eth0" "network interface of NAS to be checked (e.g. eth0, eth1, bond0,...) (valaue: $ [eth0])" 1 1
	read_config_value "NETWORK_USAGE_INTERFACE_MIN_BYTES" 1000 "Less than x bytes per second for low bandwidth (valaue: # [1000])" 1 1
	read_config_value "NETWORK_USAGE_INTERFACE_MAX_BYTES" 5000 "More than x bytes per second for high bandwidth (valaue: # [5000])" 1 1
	read_config_value "NETWORK_USAGE_INTERFACE_PROBES" 10 "number of probes to calculate active usage (valaue: # [10])" 1 1
	read_config_value "NETWORK_USAGE_INTERFACE_PROBES_POSITIVE" 7 "number of positive probes to identify active usage (valaue: # [7])" 1 1

	read_config_value "WEBSERVER_SHUTDOWN_ACTIVE" 0 "set own shutdown webserver active (valaue: 0/1 [0])" 1 1
	read_config_value "WEBSERVER_SHUTDOWN_PORT" 8080 "port number of shutdown webserver (valaue: # [8080" 1 1
	read_config_value "WEBSERVER_SHUTDOWN_PORT_EXTERNAL" 48080 "external port number of shutdown webserver (valaue: # [48080])" 1 1
	read_config_value "WEBSERVER_SHUTDOWN_URL" "shutdown" "path of shutdown webserver to execute shutdown (without prefix slash) (valaue: $)" 1 1
	read_config_value "WEBSERVER_TEST_URL" "test" "path of webserver to test functionality (without prefix slash) (valaue: $)" 1 1
	read_config_value "WEBSERVER_SHUTDOWN_SCRIPT" "autoshutdown_webserver.py" "path of shutdown webserver (valaue: $)" 1 1
	read_config_value "WEBSERVER_SHUTDOWN_WEBSITE" "shutdown initialized" "content of html feedback page (valaue: $)" 1 1
	read_config_value "MESSAGE_WEBSERVER_SHUTDOWN_START" "Shutdown Websever initialized..." "notification message if webserver is initialized (valaue: $)" 1 1
	read_config_value "MESSAGE_WEBSERVER_SHUTDOWN" "Shutdown of system initialized by webserver" "notification message if shutdown initialized by webserver (valaue: $)" 1 1
	read_config_value "WEBSERVER_MAGICKEY" "$MY_WEBSERVER_MAGICKEY_GENERATED" "Permanent magic key to access websever by IFTTT; sync with web request URL in receipe (value: $)" 0 1
	read_config_value "WEBSERVER_MAGICWORD" "abracadabra" "Permanent magic word to access websever by IFTTT; advice: change this to sometineg else (value: $ )" 0 1

	read_config_value "WEBSERVER_DMSS_RESET_URL" "reset" "path of webserver to deadman's switch (DMSS) functionality (without prefix slash) (valaue: $ [reset])" 1 1
	ini_val "${CONFIGFILE_INI}" "DMSS.WEBSERVER_DMSS_RESET_URL" "reset" "path of webserver to deadman's switch (DMSS) functionality (without prefix slash) (valaue: $ [reset])" 1 1
	read_config_value "DMSS_GRACE_EVERY" 300 "send desadman's switch (DMSS) link if system is running a long time (value: # [300}])" 1 1
	ini_val "${CONFIGFILE_INI}" "DMSS.DMSS_GRACE_EVERY" 300 "send desadman's switch (DMSS) link if system is running a long time (value: # [300}])" 1 1
	read_config_value "DMSS_EXECUTE_AFTER_GRACE" 5 "execute desadman's switch (DMSS) if user is not responding (value: # [5])" 1 1
	ini_val "${CONFIGFILE_INI}" "DMSS.DMSS_EXECUTE_AFTER_GRACE" 5 "execute desadman's switch (DMSS) if user is not responding (value: # [5])" 1 1
	read_config_value "DMSS_RESET_FILENAME" "autoshutdown.reset" "filename to reset desadman's switch (DMSS) if user is responding (value: # [5])" 1 1
	ini_val "${CONFIGFILE_INI}" "DMSS.DMSS_RESET_FILENAME" "autoshutdown.reset" "filename to reset desadman's switch (DMSS) if user is responding (value: # [5])" 1 1

	read_config_value "MESSAGE_DMSS_NOTIFY" "System is going to be shutdown if not resetted. To reset click here: #WEBSERVER_URL_DMSS_RESET#" "Notification to reset deadman's switch (DMSS) (value: $)" 1 1
	ini_val "${CONFIGFILE_INI}" "DMSS.MESSAGE_DMSS_NOTIFY" "System is going to be shutdown if not resetted. To reset click here: #WEBSERVER_URL_DMSS_RESET#" "Notification to reset deadman's switch (DMSS) (value: $)" 1 1
	read_config_value "MESSAGE_DMSS_EXECUTE_NOTIFY" "System is going to be shutdown by deadman's switch NOW" "Notification abaount execution of deadman's switch (DMSS) (value: $)" 1 1
	ini_val "${CONFIGFILE_INI}" "DMSS.MESSAGE_DMSS_EXECUTE_NOTIFY" "System is going to be shutdown by deadman's switch NOW" "Notification abaount execution of deadman's switch (DMSS) (value: $)" 1 1

	# after each config (re)load the webserver has to be starten
	# ########################################################
	# # WEBSERVER START
	if [ "$WEBSERVER_SHUTDOWN_ACTIVE" -eq 1 ];then
		init_webserver_shutdown
	fi

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

	if [ -f "$SCRIPTFILE_DEV" ]; then
    	local MD5_HASHSCRIPT_DEV
		MD5_HASHSCRIPT_DEV=$(md5sum "$SCRIPTFILE_DEV"| cut -d ' ' -f 1)

		if [ ! -f "$HASHSCRIPTFILE_DEV" ]; then
			# two ecos required, because one alone seems to be ignored
			echo "$MD5_HASHSCRIPT_DEV" > "$HASHSCRIPTFILE_DEV"
			writelog "I" "Script (dev) hash - init new hash"
			writelog "I" "$MD5_HASHSCRIPT_DEV -> $HASHSCRIPTFILE_DEV"
			echo "$MD5_HASHSCRIPT_DEV" > "$HASHSCRIPTFILE_DEV"
			writelog "I" "Script (dev) hash - hash value confirmed. No action needed."
		else
			MD5_HASHSCRIPT_DEV_SAVED=$(cat "$HASHSCRIPTFILE_DEV")
			writelog "D" "Script (dev) hash - actual hash value: $MD5_HASHSCRIPT_DEV"
			writelog "D" "Script (dev) hash - saved hash value : $MD5_HASHSCRIPT_DEV_SAVED"

			if [ "$MD5_HASHSCRIPT_DEV_SAVED" != "$MD5_HASHSCRIPT_DEV" ]; then
				# do something
				writelog "W" "Script (dev) hash - script modified, copy new version of script"
				writelog "I" "Script (dev): $SCRIPTFILE_DEV"
				writelog "I" "Script       : $SCRIPTFILE"

				cp "$SCRIPTFILE_DEV" "$SCRIPTFILE"
				writelog "I" "Script (dev) copied..."

				# two ecos required, because one alone seems to be ignored
				echo "$MD5_HASHSCRIPT_DEV" > "$HASHSCRIPTFILE_DEV"
		        writelog "W" "Script (dev) hash - dev script modified, refresh hash"
				writelog "I" "$MD5_HASHSCRIPT_DEV -> $HASHSCRIPTFILE_DEV"
				echo "$MD5_HASHSCRIPT_DEV" > "$HASHSCRIPTFILE_DEV"
			else
				writelog "I" "Script (dev) hash - hash value confirmed. No action needed."
			fi
		fi
	else
		writelog "I" "Script (dev) - dev file not present. No action needed."
		rm "$HASHSCRIPTFILE_DEV" 2>/dev/null
	fi

    local MD5_HASHSCRIPT
	MD5_HASHSCRIPT=$(md5sum "$SCRIPTFILE"| cut -d ' ' -f 1)
    # first run?
    if [ ! -f "$HASHSCRIPTFILE" ]; then
        writelog "I" "Script hash - init new hash"
        echo "$MD5_HASHSCRIPT" > "$HASHSCRIPTFILE"
    fi

    MD5_HASHSCRIPT_SAVED=$(cat "$HASHSCRIPTFILE")
    writelog "D" "Script hash : $SCRIPTFILE"
    writelog "D" "Script hash - actual hash value: $MD5_HASHSCRIPT"
    writelog "D" "Script hash - saved hash value : $MD5_HASHSCRIPT_SAVED"

    if [ "$MD5_HASHSCRIPT_SAVED" != "$MD5_HASHSCRIPT" ]; then
        # do something
        writelog "W" "Script hash - script modified, restart script"
        rm "$HASHSCRIPTFILE"
        "$0" "$@" &
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
	local BEEPS_NUM
	BEEPS_NUM="$1"
	
	for i in {1..$BEEPS_NUM}
	do
		writelog "I" "Beep."
		echo 2 > /dev/ttyS1
		sleep 1
	done
}

#######################################
# Replace placeholders in log filename
# Globals:
#   $MY_HOSTNAME
#	$LOG_TIMESTAMP_FORMAT_DATETIME
#	$LOG_TIMESTAMP_FORMAT_DATE
#	$LOG_TIMESTAMP_FORMAT_TIME
#	$PID
# Arguments:
#   $1: log filename to be converted
# Returns:
#   converted string
#######################################
replace_logfilename_placeholder()
{
	local retvar="$1"

	retvar=${retvar//#DATETIME#/$LOG_TIMESTAMP_FORMAT_DATETIME}
	retvar=${retvar//#DATE#/$LOG_TIMESTAMP_FORMAT_DATE}
	retvar=${retvar//#TIME#/$LOG_TIMESTAMP_FORMAT_TIME}
	retvar=${retvar//#PID#/$PID}
	retvar=${retvar//#HOSTNAME#/$MY_HOSTNAME}

	echo "$retvar"
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
	local retvar
	retvar="$1"

	# replace placeholders with variable content
	retvar=${retvar//#VALID_MARKER_SYSTEMS_LIST#/$VALID_MARKER_SYSTEMS_LIST}
	retvar=${retvar//#MY_START_TIME#/$MY_START_TIME}
	retvar=${retvar//#MY_HOSTNAME#/$MY_HOSTNAME}
	retvar=${retvar//#MY_PRIMARY_IP#/$MY_PRIMARY_IP}
	retvar=${retvar//#RUNLOOP_COUNTER#/$RUNLOOP_COUNTER}

	# note: loops * sleep_time
	local RUNLOOP_TIME
	RUNLOOP_TIME=$((RUNLOOP_COUNTER*SLEEP_TIMER))
	retvar=${retvar//#RUNLOOP_TIME#/$RUNLOOP_TIME}
	#local RUNLOOP_TIME_SECS=$((RUNLOOP_TIME))
	#local RUNLOOP_TIME_DAYS=$(((RUNLOOP_TIME_SECS/60*60)/24))
    #local RUNLOOP_TIME_HOURS=$(((RUNLOOP_TIME_SECS/60*60)%24))
    #local RUNLOOP_TIME_MINS=$(((RUNLOOP_TIME_SECS/60)%60))
    #local RUNLOOP_TIME_SECS=$((RUNLOOP_TIME_SECS%60))
	#retvar=${retvar//#RUNLOOP_TIME_HUMAN#/${RUNLOOP_TIME_DAYS}d:${RUNLOOP_TIME_HOURS}h:${RUNLOOP_TIME_MINS}m:${RUNLOOP_TIME_SECS}s}
	RUNLOOP_SECONDS_HUMAN=$(sec_to_time "$RUNLOOP_TIME" "long")
	retvar=${retvar//#RUNLOOP_TIME_HUMAN#/$RUNLOOP_SECONDS_HUMAN}

	local SYS_UPTIME
	SYS_UPTIME=$(awk '{print int($1)}' /proc/uptime)
	local SYS_UPTIME_HUMAN
	SYS_UPTIME_HUMAN=$(sec_to_time "$SYS_UPTIME" "long")
	retvar=${retvar//#SYS_UPTIME_HUMAN#/$SYS_UPTIME_HUMAN}

	retvar=${retvar//#WEBSERVER_URL_SHUTDOWN#/http://$MY_PUBLIC_IP:$WEBSERVER_SHUTDOWN_PORT_EXTERNAL/$MY_UUID/$WEBSERVER_SHUTDOWN_URL}
	retvar=${retvar//#WEBSERVER_URL_DMSS_RESET#/http://$MY_PUBLIC_IP:$WEBSERVER_SHUTDOWN_PORT_EXTERNAL/$MY_UUID/$WEBSERVER_DMSS_RESET_URL}

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
	local NOW
	NOW=$(date +"%d.%m.%Y %H:%M:%S")
	local MSGLEVEL="$1"
	local MSG="$2"

	# only output if NOT a "D" message or in debug mode
	if [ "$MSGLEVEL" != "D" ] || [ "$DEBUG_MODE" -eq 1 ]; then
		# use color output?
		if [ "$USE_INTERACTIVE_COLOR" == "1" ];then
			[ "$COLOR_PID" != "" ] && PID_CONSOLE="${COLOR_PID}$PID${COLOR_NC}"
			case "$MSGLEVEL" in
				D)
					[ "$COLOR_DEBUG" != "" ] && MSGLEVEL_CONSOLE="${COLOR_DEBUG}$MSGLEVEL${COLOR_NC}"
					;;
				I)
					[ "$COLOR_INFO" != "" ] && MSGLEVEL_CONSOLE="${COLOR_INFO}$MSGLEVEL${COLOR_NC}"
					;;
				W)
					[ "$COLOR_WARNING" != "" ] && MSGLEVEL_CONSOLE="${COLOR_WARNING}$MSGLEVEL${COLOR_NC}"
					;;
				E)
					[ "$COLOR_ERROR" != "" ] && MSGLEVEL_CONSOLE="${COLOR_ERROR}$MSGLEVEL${COLOR_NC}"
					;;
			esac
			echo -e "$NOW [$PID_CONSOLE] [$MSGLEVEL_CONSOLE] - $MSG"
		else
			echo "$NOW [$PID] [$MSGLEVEL] - $MSG"
		fi

		# log output
		echo "$NOW [$PID] [$MSGLEVEL] - $MSG" >>"$LOGFILE"
	fi

	# shorten logfile to max line number if not set to zero (0)
	if [ $LOGFILE_MAXLINES -ne 0 ]; then
		# log rotate dynamic logfile
		tail -n "$LOGFILE_MAXLINES" "$LOGFILE" >"$LOGFILE.temp"
		rm "$LOGFILE"
		mv "$LOGFILE.temp" "$LOGFILE"
	fi
}

#######################################
# Send notification to Synology DSM
# Globals:
#	-
# Arguments:
#	$1: Message
# Returns:
#   -
#######################################
dsm_notification()
{
	local MY_MESSAGE=$1

	DSMNOTIFY_EXISTS=$(command -v synodsmnotify|wc -l)
	if [ "$DSMNOTIFY_EXISTS" -eq 1 ]; then
		writelog "I" "DSM notification sent"
		synodsmnotify "@administrators" "$APP_NAME" "$MY_MESSAGE"
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
	local MY_IDENTIFIER="$1"
	local MY_MESSAGE="$2"

	if [ "x$IFTTT_KEY" != "x" ]; then
		if [ "x$IFTTT_EVENT" != "x" ]; then
			if [ "x$MY_IDENTIFIER" != "x" ]; then
				writelog "D" "IFTTT Notification NAME  : $MY_IDENTIFIER"
				writelog "D" "IFTTT Notification STATUS:$MY_MESSAGE"
				writelog "D" "IFTTT Notification EVENT :$IFTTT_EVENT"
				writelog "D" "IFTTT Notification KEY   : $IFTTT_KEY"
				writelog "D" "{\"value1\":\"$MY_IDENTIFIER - $MY_MESSAGE\"} https://maker.ifttt.com/trigger/$IFTTT_EVENT/with/key/$IFTTT_KEY"
				curl -X POST -H "Content-Type: application/json" -d "{\"value1\":\"$APP_NAME: $MY_IDENTIFIER - $MY_MESSAGE\"}" "https://maker.ifttt.com/trigger/$IFTTT_EVENT/with/key/$IFTTT_KEY" >/dev/null 2>&1
				writelog "I" "IFTTT Notification sent: $MY_MESSAGE"

				dsm_notification "$MY_MESSAGE"
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

#######################################
# Check network usage (to check deep sleep systems)
# Globals:
#   $NETWORK_USAGE_INTERFACE
#	$NETWORK_USAGE_INTERFACE_MIN_BYTES
#	$NETWORK_USAGE_INTERFACE_MAX_BYTES
#	$NETWORK_USAGE_INTERFACE_PROBES_POSITIVE
# Arguments:
#	-
# Returns:
#   0/1 status of usage 
#######################################
is_network_in_use() {
    COUNT_HIGH=0
    BYTES_DIFF_MAX=0
    #BYTES=$(ifconfig $NW_DEVICE|grep "TX bytes"|cut -d ":" -f 3|cut -d " " -f 1)
    BYTES=$(cat "/sys/class/net/$NETWORK_USAGE_INTERFACE/statistics/rx_bytes")
    for i in {0..10}
    do
#    while true; do 
        BYTES_SAVE="$BYTES"
        #BYTES=$(ifconfig $NW_DEVICE|grep "TX bytes"|cut -d ":" -f 3|cut -d " " -f 1)
        BYTES=$(cat "/sys/class/net/$NETWORK_USAGE_INTERFACE/statistics/rx_bytes")
        BYTES_DIFF=$((BYTES-BYTES_SAVE))
        DIFF_CODE="NORMAL"
        if [ "$BYTES_DIFF" -gt "$BYTES_DIFF_MAX" ]; then
            BYTES_DIFF_MAX=$BYTES_DIFF
        fi
        if [ "$BYTES_DIFF" -lt "$NETWORK_USAGE_INTERFACE_MIN_BYTES" ];then
            DIFF_CODE="  LOW"
        fi
        if [ "$BYTES_DIFF" -gt "$NETWORK_USAGE_INTERFACE_MAX_BYTES" ];then
            DIFF_CODE=" HIGH "
            COUNT_HIGH=$((COUNT_HIGH+1))
        fi
        #echo "$BYTES ($BYTES_DIFF) $DIFF_CODE (max: $BYTES_DIFF_MAX)"
        #echo "$BYTES ($BYTES_DIFF) $DIFF_CODE (max: $BYTES_DIFF_MAX)" >>/volume1/control/syno_autoshutdown/net.txt
        sleep 1
    done
    if [ "$COUNT_HIGH" -ge "$NETWORK_USAGE_INTERFACE_PROBES_POSITIVE" ]; then
        echo 1
    else
        echo 0
    fi    
}

#######################################
# Restart loop if valid systems found
# Globals:
#   $FOUND_SYSTEMS
#	$VALID_MARKER_SYSTEMS_LIST
# Arguments:
#	-
# Returns:
#   MAXLOOP_COUNTER=0
#######################################
restart_loop() {
	# reset counter
	MAXLOOP_COUNTER=0
	writelog "I" "$FOUND_SYSTEMS marker systems found. Resetting loop."
	### Trim whitespaces ###
	VALID_MARKER_SYSTEMS_LIST=$(echo "$VALID_MARKER_SYSTEMS_LIST" | sed -e 's/^[[:space:]]*//')
	# replace spaces with ", "
	VALID_MARKER_SYSTEMS_LIST=${VALID_MARKER_SYSTEMS_LIST// /, }

	local RET
	RET=$(replace_placeholder "Found system names: #VALID_MARKER_SYSTEMS_LIST#")
	writelog "I" "$RET"
}

#######################################
# Check and notify if valid systems are found again
# Globals:
#   $MAXLOOP_COUNTER
#	$RUNLOOP_COUNTER
#	$NOTIFY_ON_STATUS_CHANGE
#	$MESSAGE_STATUS_CHANGE_VAL
# Arguments:
#	-
# Returns:
#   -
#######################################
notify_restart_loop() {
	local RET
	if [ $MAXLOOP_COUNTER -ne 0 ]; then
		if [ $RUNLOOP_COUNTER -gt 1 ]; then
		writelog "I" "--> status change (not found -> found)"
			# only send notification after first loop
			if [ "$NOTIFY_ON_STATUS_CHANGE" -eq "1" ];then
				RET=$(replace_placeholder "$MESSAGE_STATUS_CHANGE_VAL")
				writelog "I" "Sending notification (MESSAGE_STATUS_CHANGE_VAL)"
				notification "$MYNAME" "$RET"
				writelog "I" "Notification sent: $RET"
			fi
		fi
	fi
}

notify_stop_loop() {
	writelog "I" ""
}

# ########################################################
# ########################################################
# # MAIN PROGRAM
# ########################################################
# ########################################################

#if pidof -o %PPID -x $SCRIPTFILE>/dev/null; then
#	echo "Process already running"
#fi

read_config_value "LOGFILE_FILENAME" "autoshutdown.log" "define log filename; placeholder optionally (#DATETIME#) (value: $)" 0 0
LOGFILE=$(replace_logfilename_placeholder "$LOGFILE_FILENAME")
LOGFILE="$THISDIR/$LOGFILE"

# ########################################################
# # INTRO HEADER
writelog "I" "################################################################################"
writelog "I" "#####"
writelog "I" "##### $APP_NAME"
writelog "I" "#####"
writelog "I" "##### Version $APP_VERSION, $APP_DATE"
writelog "I" "##### $APP_SOURCE"
writelog "I" "##### Licensed under APLv2"
writelog "I" "#####"
writelog "I" "################################################################################"
writelog "I" "base directory: $THISDIR"
writelog "I" "own primary ip: $MY_PRIMARY_IP"
writelog "I" "scan ip range : $MY_SCAN_RANGE.*"

writelog "I" "Removing old (7 days) logs"
DUMMY=$(find "$THISDIR/" -type f -mtime +$LOGFILE_CLEANUP_DAYS -name 'autoshutdown_*.log' -exec rm {} \;)

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
                *) ARG_A="$2" ; shift 2 ;;
            esac ;;
        -v|--verbose) OPT_VERBOSE=1 ; shift ;;
        -k|--killall) OPT_KILLALL=1 ; shift ;;
		-r|--resetlog) OPT_RESETLOG=1; shift;;
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
	rm "$LOGFILE"
	OPT_RESETLOG=0
fi

# ########################################################
# # MAIN LOOP
# cleanup hash file (create new configfile)
rm "$HASHFILE"
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
	RUNLOOP_MODULA=$((RUNLOOP_COUNTER % NOTIFY_ON_LONGRUN_EVERY))
	if [ $RUNLOOP_MODULA -eq 0 ];then
		writelog "I" "Sending notification (MESSAGE_LONGRUN)"

		MESSAGE_LONGRUN_NOTIFY=$(replace_placeholder "$MESSAGE_LONGRUN")
		notification "$MYNAME" "$MESSAGE_LONGRUN_NOTIFY"
		writelog "I" "Notification sent: $MESSAGE_LONGRUN_NOTIFY"
	fi

	DMSS_MODULA=$((RUNLOOP_COUNTER % DMSS_GRACE_EVERY))
	if [ $DMSS_ACTIVE -eq 0 ]; then
		# if DMSS is inactive
		if [ $DMSS_MODULA -eq 0 ];then
			writelog "I" "Sending notification (MESSAGE_DMSS)"

			MESSAGE_DMSS=$(replace_placeholder "$MESSAGE_DMSS_NOTIFY")
			notification "$MYNAME" "$MESSAGE_DMSS"
			writelog "I" "Notification sent: $MESSAGE_DMSS"
			DMSS_ACTIVE=1
		fi
	else
		# if DMSS is active
		DMSS_ACTIVE_COUNTER=$((DMSS_ACTIVE_COUNTER+1))
		writelog "D" "Check file exists: $THISDIR/$DMSS_RESET_FILENAME"
		if [ -f "$THISDIR/$DMSS_RESET_FILENAME" ]; then
			writelog "I" "Forced shutdown grace timer was reset by user"
			rm "$THISDIR/$DMSS_RESET_FILENAME"
			DMSS_ACTIVE=0
			DMSS_ACTIVE_COUNTER=0
		fi
		if [ $DMSS_ACTIVE_COUNTER -ge "$DMSS_EXECUTE_AFTER_GRACE" ]; then
			notification "$MYNAME" "$MESSAGE_DMSS_EXECUTE_NOTIFY"
			writelog "W" "System is going to be shutdown by deadman's switch"
			poweroff
		fi
	fi


	if [ $ACTIVE_STATUS -ne 1 ]; then
		writelog "I" "Autoshutdown (temporary?) disabled. Waiting for next check in $SLEEP_TIMER seconds..."
	else
		writelog "I" "Checking systems (loop $MAXLOOP_COUNTER of $SLEEP_MAXLOOP; $SLEEP_TIMER seconds waiting time)"

		# get all online IP addresses
		FOUND_HOSTS=$(for i in {1..254} ;do (ping "$MY_SCAN_RANGE.$i" -c 1 -w 5  >/dev/null && echo "$MY_SCAN_RANGE.$i" &) ;done)
		# search local network
		for FOUND_IP in $FOUND_HOSTS
		do
			# match marker systems with online systems (IP based)
			# note: space is important to find this IP (CHECKHOSTS has an additional space at end)

			if [[ "$CHECKHOSTS" =~ "$FOUND_IP " ]]; then
#			if grep -q "$FOUND_IP " <<< "$CHECKHOSTS"; then
					# -----------------------------------------------
					# IP check
					# -----------------------------------------------
					DUMMY="System (IP)"
					VALID_MARKER_SYSTEMS_LIST="$VALID_MARKER_SYSTEMS_LIST$FOUND_IP "
					FOUND_SYS=$(get_hostname_from_ip "$FOUND_IP")
					FOUND_SYS=$(string_to_lower "$FOUND_SYS")
					DUMMY="$DUMMY [$FOUND_IP -> $FOUND_SYS] - valid marker system"
					FOUND_SYSTEMS=$((FOUND_SYSTEMS+1))
					writelog "I" "$DUMMY"
			else
				# -----------------------------------------------
				# HOSTNAME check
				# -----------------------------------------------
				# match marker systems with online systems (IP translated in hostname)
				FOUND_SYS=$(nslookup "$FOUND_IP" | awk '/name/ {split ($4,elems,"."); print elems[1]}')
				if [ "$CHECKHOSTS_IGNORE_MULTI_HOSTNAMES" -eq 1 ]; then
					# ignore all names except the first one.
					FOUND_SYS=$(echo "$FOUND_SYS"|head -n 1)
				fi
				FOUND_SYS=$(string_to_lower "$FOUND_SYS")
				writelog "D" "FOUND_SYS (lower)=$FOUND_SYS"
				# find multi hostname systems (e.g. fritzbox)
				FOUND_SYS_LINES=$(echo "$FOUND_SYS"|wc -l)
				# check valid ip address (vs. multiple hostnames)
				if [[ "$FOUND_SYS_LINES" -eq 1 ]]; then
					# only accept single-line matches (unique hostnames)
					if [ ! -z "$FOUND_SYS" ]; then
						CHECKHOSTS=$(echo "$CHECKHOSTS" | tr '[A-Z]' '[a-z]')
						FOUND_SYS=$(echo "$FOUND_SYS" | tr '[A-Z]' '[a-z]')
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

		# -----------------------------------------------
		# main check to keep loop running...
		# -----------------------------------------------
		if [ $FOUND_SYSTEMS -ge 1 ]; then
			# -----------------------------------------------
			# one or more systems found?
			# -----------------------------------------------
			# special check: test network usage - if low, system in connected but not using the NAS
			if [ "$FOUND_SYSTEMS" -eq 1 ]; then
				# -----------------------------------------------
				# just one system in list?
				# -----------------------------------------------
				VALID_MARKER_SYSTEMS_LIST=$(echo "$VALID_MARKER_SYSTEMS_LIST" | sed -e 's/^[[:space:]]*//')
				if [[ $CHECKHOSTS_DEEPSLEEP =~ $VALID_MARKER_SYSTEMS_LIST ]]; then
					# -----------------------------------------------
					# just one last deep sleep system!
					# -----------------------------------------------
					# last system is a deep sleep system, so check network usage
					writelog "I" "Last system '$VALID_MARKER_SYSTEMS_LIST' is a defined deep sleep system."

					writelog "I" "Checking network usage... Waiting..."
					NETWORK_USEAGE_CHECK=$(is_network_in_use)
					if [ "$NETWORK_USEAGE_CHECK" -eq 1 ]; then
						# network has high usage
						writelog "I" "Network usage is high."
						restart_loop
					else
						writelog "I" "Network usage is low. Keep loop running..."
						MAXLOOP_COUNTER=$((MAXLOOP_COUNTER+1))
#						notification "$MYNAME" "$MESSAGE_LAST_SYSTEM_DEEPSLEEP"
					fi
				else
					# -----------------------------------------------
					# other than a deep sleep system!
					# -----------------------------------------------
					notify_restart_loop
					restart_loop
				fi
			else
				# -----------------------------------------------
				# more than one system found!
				# -----------------------------------------------
				notify_restart_loop
				restart_loop
			fi
		else
			# -----------------------------------------------
			# now no systems found
			# -----------------------------------------------
			# note: former status is system found (incremented loop counter)
			if [ $MAXLOOP_COUNTER -eq 0 ]; then
				# status change detected?
				writelog "I" "--> status change (found -> not found)"
				if [ $RUNLOOP_COUNTER -gt 1 ]; then
					# only send notification after first loop
					if [ $NOTIFY_ON_STATUS_CHANGE -eq 1 ];then
						RETURN_VAR=$(replace_placeholder "$MESSAGE_STATUS_CHANGE_INV")
						writelog "I" "Sending notification (MESSAGE_STATUS_CHANGE_INV)"
						notification "$MYNAME" "$RETURN_VAR"
						writelog "I" "Notification sent: $RETURN_VAR"
					fi
				fi
			fi
			# increment counter
			MAXLOOP_COUNTER=$((MAXLOOP_COUNTER+1))
			writelog "W" "No marker systems found. Proceeding with loop. ($MAXLOOP_COUNTER of $SLEEP_MAXLOOP)"
		fi

		# -----------------------------------------------
		# counter > grace timer?
		# -----------------------------------------------
		if [ "$MAXLOOP_COUNTER" -ge $GRACE_TIMER ];then
			# counter = grace timer?
			if [ "$MAXLOOP_COUNTER" -eq $GRACE_TIMER ];then
				# send notification
				if [ "$NOTIFY_ON_GRACE_START" -eq 1 ];then
					writelog "I" "Sending notification (NOTIFY_ON_GRACE_START)"
					MESSAGE_GRACE_START_NOTIFY=$(replace_placeholder "$MESSAGE_GRACE_START")
					notification "$MYNAME" "$MESSAGE_GRACE_START_NOTIFY"
					writelog "I" "Notification sent: $MESSAGE_GRACE_START_NOTIFY"
				fi
			else
				# send notification on every ... ?
				if [ "$NOTIFY_ON_GRACE_EVERY" -eq 1 ];then
					writelog "I" "Sending notification (NOTIFY_ON_GRACE_EVERY)"
					MESSAGE_GRACE_EVERY_NOTIFY=$(replace_placeholder "$MESSAGE_GRACE_EVERY")
					notification "$MYNAME" "$MESSAGE_GRACE_EVERY_NOTIFY"
					writelog "I" "Notification sent: $MESSAGE_GRACE_EVERY_NOTIFY"
				fi
			fi
			
			# beep on every loop in grace period?
			if [ "$GRACE_BEEP" -eq 1 ];then
				beeps "$GRACE_BEEP_COUNT"
			fi
		fi

		# summary
		RUNLOOP_COUNTER_TIME=$((RUNLOOP_COUNTER*SLEEP_TIMER))
		RUNLOOP_COUNTER_HRF=$(sec_to_time "$RUNLOOP_COUNTER_TIME" "long")

		SYS_UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime)
		SYS_UPTIME_HUMAN=$(sec_to_time "$SYS_UPTIME_SECONDS" "long")

		writelog "I" "#####################################################"
		writelog "I" "#####"
		writelog "I" "#####  ===== S U M M A R Y (last cycle) ====="
		writelog "I" "#####"
		writelog "I" "##### System uptime:"
		writelog "I" "#####     $SYS_UPTIME_HUMAN"
		writelog "I" "#####"
		writelog "I" "##### Overall elapsed cycles:"
		writelog "i" "#####     $RUNLOOP_COUNTER cycle(s) since script (re-)start"
		writelog "I" "#####     $RUNLOOP_COUNTER_HRF ($RUNLOOP_COUNTER_TIME secs.)"
		writelog "I" "#####"
		writelog "I" "##### Inactive system loop cycles:"
		writelog "I" "#####     $FOUND_SYSTEMS valid marker system(s) found"
		writelog "I" "#####     $MAXLOOP_COUNTER cycles of max $SLEEP_MAXLOOP cycles "
		writelog "I" "#####"
		writelog "I" "##### Long running cycle checks:"
		writelog "I" "#####     $RUNLOOP_MODULA (modula) cycle(s) of every $NOTIFY_ON_LONGRUN_EVERY cycles"
		writelog "I" "#####"
		writelog "I" "##### Deadman's switch:"
		writelog "I" "#####     $DMSS_MODULA (modula) cycle(s) of every $DMSS_GRACE_EVERY cycles"
		writelog "I" "#####     DMSS active: $DMSS_ACTIVE"
		writelog "I" "#####     $DMSS_ACTIVE_COUNTER grace cycle(s) of max $DMSS_EXECUTE_AFTER_GRACE cycle(s)"
		writelog "I" "#####"
		writelog "I" "#####################################################"

		# check if loop > maxloop?
		if [ "$MAXLOOP_COUNTER" -ge $SLEEP_MAXLOOP ]; then
			# check if still no system found
#			if [ $FOUND_SYSTEMS -eq 0 ]; then
#				writelog "I" "STATUS: All systems still offline!"
			writelog "I" "Shutting down this system... Sleep well :)"
			# send notification on system shutdown?
			if [ "$NOTIFY_ON_SHUTDOWN" -eq 1 ];then
				MESSAGE_SLEEP=$(replace_placeholder "$MESSAGE_SLEEP")
				notification "$MYNAME" "$MESSAGE_SLEEP"
				writelog "I" "Notification sent: $MESSAGE_SLEEP"
			fi
			# beep on system shutdown?
			if [ "$SHUTDOWN_BEEP" -eq 1 ];then
				beeps "$SHUTDOWN_BEEP_COUNT"
			fi
			poweroff
			writelog "I" "#####################################################"
			writelog "I" "#####                 G O O D B Y                    "
			writelog "I" "#####################################################"
			sleep 60
			exit 0
#			fi
		fi
		writelog "I" "Waiting for next check in $SLEEP_TIMER seconds..."
		writelog "I" ""
		writelog "I" ""
	fi
	
	# sleep till next loop
	sleep "$SLEEP_TIMER"

done;