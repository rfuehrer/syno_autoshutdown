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

THISDIR=`dirname $0`
THISDIR=`dirname $(realpath $0)`
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
LOG_TIMESTAMP_FORMAT=$(date +%Y%m%d_%H%M%S)

SLEEP_TIMER=10
SLEEP_MAXLOOP=180
GRACE_TIMER=4
LOGFILE_MAXLINES=100000
LOGFILE_CLEANUP_DAYS=7

CONFIGFILE=autoshutdown.config
LOGFILE=autoshutdown_$LOG_TIMESTAMP_FORMAT.log
HASHFILE=autoshutdown.hash
HASHSCRIPTFILE=autoshutdown.pidhash
PID=$BASHPID

MY_PRIMARY_IP=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
MY_SCAN_RANGE=`echo $MY_PRIMARY_IP | cut -d. -f-3`


# ------- DO NOT EDIT BELOW THIS LINE -------
SCRIPTFILE=`basename "$0"`
TEMPDIR=$THISDIR
HOSTNAME=`hostname`
if [ "z$HOSTNAME" != "z" ]; then
    CONFIGFILE="autoshutdown-$HOSTNAME.config"
	if [ ! -f "$THISDIR/$CONFIGFILE" ]; then
		# fallback config (generic)
    	CONFIGFILE="autoshutdown.config"
	fi
fi
SCRIPTFILE=$THISDIR/$SCRIPTFILE
LOGFILE=$THISDIR/$LOGFILE
CONFIGFILE=$THISDIR/$CONFIGFILE
HASHFILE=$THISDIR/$HASHFILE

ACTION_DO=1
APP_VERSION=1.6
APP_DATE=22.10.2019
APP_AUTHOR=Rene

MAXLOOP_COUNTER=0


# -------------------------------------------
 
read_config() {
  MD5_HASH_SAVED=($(cat $HASHFILE))
  MD5_HASH_CONFIG=($(md5sum $CONFIGFILE| cut -d ' ' -f 1))
  writelog "config : $HOSTNAME : $CONFIGFILE"
  writelog "config - actual hash value: $MD5_HASH_CONFIG"
  writelog "config - saved hash value : $MD5_HASH_SAVED"

  if [ "$MD5_HASH_SAVED" != "$MD5_HASH_CONFIG" ]; then
    writelog "config - modified, reload config"

    # save hash value
    echo $MD5_HASH_CONFIG > $HASHFILE

    # reload config
    writelog "(Re-)Reading config file..."
  	CHECKHOSTS=`cat $CONFIGFILE | grep "^CHECKHOSTS" | cut -d= -f2`
	CHECKHOSTS="$CHECKHOSTS "
    writelog "Set CHECKHOSTS to value $CHECKHOSTS"
  	
	MYNAME=`cat $CONFIGFILE | grep "^MYNAME" | cut -d= -f2`
    writelog "Set MYNAME to value $MYNAME"
  	
	ACTIVE_STATUS=`cat $CONFIGFILE | grep "^ACTIVE_STATUS" | cut -d= -f2`
    writelog "Set ACTIVE_STATUS to value $ACTIVE_STATUS"
  	
	SLEEP_TIMER=`cat $CONFIGFILE | grep "^SLEEP_TIMER" | cut -d= -f2`
    writelog "Set SLEEP_TIMER to value $SLEEP_TIMER"
    
	SLEEP_MAXLOOP=`cat $CONFIGFILE | grep "^SLEEP_MAXLOOP" | cut -d= -f2`
    writelog "Set SLEEP_MAXLOOP to value $SLEEP_MAXLOOP"
    
	GRACE_TIMER=`cat $CONFIGFILE | grep "^GRACE_TIMER" | cut -d= -f2`
    writelog "Set GRACE_TIMER to value $GRACE_TIMER"
    
	LOGFILE_MAXLINES=`cat $CONFIGFILE | grep "^LOGFILE_MAXLINES" | cut -d= -f2`
    writelog "Set LOGFILE_MAXLINES to value $LOGFILE_MAXLINES"
	LOGFILE_CLEANUP_DAYS=`cat $CONFIGFILE | grep "^LOGFILE_CLEANUP_DAYS" | cut -d= -f2`
    writelog "Set LOGFILE_CLEANUP_DAYS to value $LOGFILE_CLEANUP_DAYS"

	IFTTT_KEY=`cat $CONFIGFILE | grep "^IFTTT_KEY" | cut -d= -f2`
    writelog "Set IFTTT_KEY to magic value"

	IFTTT_EVENT=`cat $CONFIGFILE | grep "^IFTTT_EVENT" | cut -d= -f2`
    writelog "Set IFTTT_EVENT to value $IFTTT_EVENT"

    SLEEP_MESSAGE=`cat $CONFIGFILE | grep "^SLEEP_MESSAGE" | cut -d= -f2 | sed -e 's/ /%20/g'`
    GRACE_MESSAGE=`cat $CONFIGFILE | grep "^GRACE_MESSAGE" | cut -d= -f2 | sed -e 's/ /%20/g'`
    SHUTDOWN_BEEP=`cat $CONFIGFILE | grep "^SHUTDOWN_BEEP" | cut -d= -f2`
    SHUTDOWN_COUNT_BEEP=`cat $CONFIGFILE | grep "^SHUTDOWN_COUNT_BEEP" | cut -d= -f2`
    GRACE_BEEP=`cat $CONFIGFILE | grep "^GRACE_BEEP" | cut -d= -f2`
    GRACE_COUNT_BEEP=`cat $CONFIGFILE | grep "^GRACE_COUNT_BEEP" | cut -d= -f2`
  else
	    writelog "config - hash confirmed. No action needed."
  fi
}

check_pidhash(){
    MD5_HASHSCRIPT=($(md5sum $SCRIPTFILE| cut -d ' ' -f 1))
    # first run?
    if [ ! -f $HASHSCRIPTFILE ]; then
        writelog "script - init new hash"
        echo $MD5_HASHSCRIPT > $HASHSCRIPTFILE
    fi
    MD5_HASHSCRIPT_SAVED=($(cat $HASHSCRIPTFILE))
    writelog "script : $SCRIPTFILE"
    writelog "script - actual hash value: $MD5_HASHSCRIPT"
    writelog "script - saved hash value : $MD5_HASHSCRIPT_SAVED"
    if [ "$MD5_HASHSCRIPT_SAVED" != "$MD5_HASHSCRIPT" ]; then
        # do something
        writelog "script - modified, restart script"
        rm $HASHSCRIPTFILE
        $0 "$@" &
        exit 0
    else
        writelog "script - hash confirmed. No action needed."
    fi
}

beeps() {
	for i in {1..$1}
	do
		echo 2 > /dev/ttyS1
		sleep 1
	done
#  echo 2 > /dev/ttyS1
#	sleep 1
#  echo 2 > /dev/ttyS1
#	sleep 1
#  echo 2 > /dev/ttyS1
}

writelog()
{
	NOW=$(date +"%d.%m.%Y %H:%M:%S")
	echo $NOW [$PID] - $1
	echo $NOW [$PID] - $1 >>$LOGFILE

	if [ $LOGFILE_MAXLINES -ne 0 ]; then
		# log rotate
		COUNT_LINES=`wc -l < "$LOGFILE"`
		tail -n $LOGFILE_MAXLINES $LOGFILE >$LOGFILE.temp
		rm $LOGFILE
		mv $LOGFILE.temp $LOGFILE
	fi
}

notification()
{
	# $1: system (myname)
	# $2: message
	if [ "x$1" != "x" ]; then
		MY_NAME=$1
		SYNO_STATUS=$2
		curl -X POST -H "Content-Type: application/json" -d "{\"value1\":\"$MY_NAME - $SYNO_STATUS\"}" https://maker.ifttt.com/trigger/$IFTTT_EVENT/with/key/$IFTTT_KEY
	fi
}


#if pidof -o %PPID -x $SCRIPTFILE>/dev/null; then
#	echo "Process already running"
#fi

writelog ""
writelog ""
writelog ""
writelog ""
writelog ""
writelog "################################################################################"
writelog "#####"
writelog "##### autoshutdown.sh  for Synology-NAS"
writelog "#####"
writelog "##### Version $APP_VERSION, $APP_DATE by $APP_AUTHOR"
writelog "#####"
writelog "################################################################################"
writelog "base directory: $THISDIR"
writelog "own primary ip: $MY_PRIMARY_IP"
writelog "scan ip range : $MY_SCAN_RANGE.*"

writelog "Removing old (7 days) logs"
DUMMY=`find $THISDIR/ -type f -mtime +$LOGFILE_CLEANUP_DAYS -name 'autoshutdown_*.log' -exec rm {} \;`
writelog ""

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
	writelog "Terminating myself because of manual kill switch"
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



# cleanup hash file (create new configfile)
rm $HASHFILE

writelog ""

while true; do
    read_config
    check_pidhash
	ACTION_DO=1
	FOUND_SYSTEMS=0
	if [ $ACTIVE_STATUS != "1" ]; then
		writelog "Autoshutdown (temporary?) disabled. Waiting for next check in $SLEEP_TIMER seconds..."
	else
		writelog "Checking systems (loop $MAXLOOP_COUNTER of $SLEEP_MAXLOOP; $SLEEP_TIMER seconds waiting time)"
		#notification "PROWL" "TEST" "$MAXLOOP_COUNTER%20of%20$SLEEP_MAXLOOP" "0"

		# get all online IP addresses
		FOUND_HOSTS=$(for i in {1..254} ;do (ping $MY_SCAN_RANGE.$i -c 1 -w 5  >/dev/null && echo "$MY_SCAN_RANGE.$i" &) ;done)
		# search local network
		for FOUND_IP in $FOUND_HOSTS
		do
			#
			# match marker systems with online systems (IP based)
			#
			# space is important to find this IP (CHECKHOSTS has an additional space at end)
			if grep -q "$FOUND_IP " <<< "$CHECKHOSTS"; then
					DUMMY="System (IP)"
					DUMMY="$DUMMY [$FOUND_IP] - valid marker system"
					FOUND_SYSTEMS=$((FOUND_SYSTEMS+1))
					ACTION_DO=0
					MAXLOOP_COUNTER=0
					writelog "$DUMMY"
			else
				#
				# match marker systems with online systems (IP translated in hostname)
				#
				FOUND_SYS=$(nslookup $FOUND_IP | awk '/name/ {split ($4,elems,"."); print elems[1]}')
				# find multi hostname systems (e.g. fritzbox)
				FOUND_SYS_LINES=$(nslookup $FOUND_IP | awk '/name/ {split ($4,elems,"."); print elems[1]}'| wc -l)
				# check valid ip address (vs. multiple hostnames)
				if [[ $FOUND_SYS_LINES -eq 1 ]]; then
						# only accept ssingle-line matches (unique hostnames)
					if [ ! -z $FOUND_SYS ]; then
						CHECKHOSTS=`echo $CHECKHOSTS | tr '[A-Z]' '[a-z]'`
						FOUND_SYS=`echo $FOUND_SYS | tr '[A-Z]' '[a-z]'`
						DUMMY="System '$FOUND_SYS' "
						if grep -q "$FOUND_SYS" <<< "$CHECKHOSTS" ; then
							DUMMY="$DUMMY [$FOUND_IP] - valid marker system"
							FOUND_SYSTEMS=$((FOUND_SYSTEMS+1))
							ACTION_DO=0
							MAXLOOP_COUNTER=0
						else
							DUMMY="$DUMMY - not decisive"
						fi
						writelog "$DUMMY"
					fi
				else
					writelog "multiple hostname system [$FOUND_IP] - ignore"
				fi
			fi
		done

		# if variable couldn't be resetted
		if [ $ACTION_DO == 1 ]; then
			#(( MAXLOOP_COUNTER = $MAXLOOP_COUNTER + 1 ))
			MAXLOOP_COUNTER=$((MAXLOOP_COUNTER+1))
		else
			writelog "$FOUND_SYSTEMS marker systems found. Resetting loop."
		fi
		if [ $MAXLOOP_COUNTER -eq $GRACE_TIMER ];then
			notification "$MYNAME" "$GRACE_MESSAGE"
			if [ $GRACE_BEEP == "1" ];then
				beeps
			fi
		fi
		writelog "#####################################################"
		writelog "#####                                                "
		writelog "#####        S H U T D O W N  C O U N T E R          "
		writelog "#####                                                "
		writelog "#####                   $MAXLOOP_COUNTER / $SLEEP_MAXLOOP             "
		writelog "#####                                                "
		writelog "#####################################################"

		if [ $MAXLOOP_COUNTER -ge $SLEEP_MAXLOOP ]; then
			if [ $ACTION_DO == 1 ]; then
				writelog "STATUS: All systems still offline!"
				writelog "Shutting down this system... Sleep well :)"
				notification "$MYNAME" "$SLEEP_MESSAGE"
				# notification "PROWL" "$MYNAME" $SLEEP_MESSAGE 7000

				if [ $SHUTDOWN_BEEP == "1" ];then
					beeps
				fi
				poweroff
			fi
		fi
		writelog "Waiting for next check in $SLEEP_TIMER seconds..."
	fi
   sleep $SLEEP_TIMER

done;