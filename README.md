# Synology Autoshutdown

A simple shell script to shutdown a Synology NAS if no authorized client is online. The main purpose of this script is to reduce power consumption. 

# Table of content
- [Synology Autoshutdown](#synology-autoshutdown)
- [Table of content](#table-of-content)
  - [Purpose](#purpose)
  - [Basic mechanism](#basic-mechanism)
  - [Functions/features](#functionsfeatures)
  - [Advantages](#advantages)
  - [Disadvantages](#disadvantages)
  - [Important note:](#important-note)
  - [Prerequisites](#prerequisites)
  - [Presumption](#presumption)
  - [Logic](#logic)
  - [Installation](#installation)
    - [Shell Script](#shell-script)
    - [Task (Scheduler)](#task-scheduler)
    - [IFTTT (Notification) (optional)](#ifttt-notification-optional)
    - [Webserver (shutdown)](#webserver-shutdown)
    - [Alexa speech commands](#alexa-speech-commands)
  - [Placeholder variables](#placeholder-variables)
    - [Notifications](#notifications)
    - [Log filename](#log-filename)
  - [Other files](#other-files)
      - [autoshutdown.hash](#autoshutdownhash)
      - [autoshutdown.pid](#autoshutdownpid)
      - [autoshutdown.pidhash](#autoshutdownpidhash)


## Purpose

The NAS can be used to store media content. If you want to access them, the system is switched on manually or by wake-on-lan. The system is in operation during this time. But what happens if the client is no longer online? The NAS continues to run and goes into standby - but it usually continues to consume power. 
This script helps to turn off the system completely and thus save power; since media access usually only has a comparatively short duration. The next time the system is accessed, it is started again manually or by wake-on-lan.

The script also has the advantage that no inflated packages need to be installed on the NAS that could compromise the security or stability of the system. If you want to keep the system as clean as possible and know which features are running on the system, open source and a shell script is just what you need :)

## Basic mechanism
At definable intervals, all systems of the current network segment (e.g. 10.0.0.x) are checked whether they are reachable. If a system could be detected, this is compared with the list of systems that were defined to avoid a shutdown. If no system could be found, the system continues to attempt to find systems for a defined period of time. If no systems are found during this time, the system is shut down. A named system found resets this check.

## Functions/features
- Bash Script (easy setup)
- Out-of-the-box usable - no installation of other toos required (no system modification!)		
- Use of simple functions from Busy Box (no dependencies)
- Connection to IFTTT (optional)
- Logging
- Self-inititalizing (with default values if no config is specified) 		
- Self-restarting (on code changes)		
- Self-reconfiguring (on config changes)		
- Self-initializing of config file and missing config options
- Warning times
- Support of beep output to the internal NAS loudspeaker
- Lightweight python webserver to shutdown NAS promptly
- Alexa integration (via IFTTT webrequests)

## Advantages
- simple solution
- Use on different NAS possible
- easy maintenance
- Expandable
- Support for electricity saving

## Disadvantages
- Increased start times due to cold start of the NAS

## Important note:

On some systems, a system in standby continues to respond to pings from this script. These systems prevent the NAS from shutting down. This is especially the case for Mac systems that use Power Nap or do not use Safe Sleep Mode. Please check how systems behave in standby mode before using the script productively.

## Prerequisites
- NAS (Synology with BusyBox like linux; tested and verified on _Linux xxxx 3.10.105 #24922 SMP Wed Jul 3 16:35:48 CST 2019 x86_64 GNU/Linux synology_cedarview_xxxxx_)
- own volume (recommended)
- SSH access (recommended)
- Scheduler (e.g. Cron) with possibility to execute shell scripts

## Presumption
- Installation on a Synology with DSM 6.x

## Logic		
 ![logic_diagram](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/logic_diagram.png)	
  ```		
 Title Synology Autoshutdown (main loop)		
 Init->Config: 		
 Config->Check IP: 		
 loop main loop		
     Check IP->Check hostname: found IP not specified		
     Check hostname->Check IP: >1 Systems found		
     Check hostname->Check deep sleep: =1 system found		
     Check hostname->Observation phase: <1 system found		
     Check deep sleep->Check IP: high traffic		
     Check deep sleep->Observation phase: low traffic		
     Check IP->Observation phase: no system found		
     Check deep sleep->Observation phase: no system found		
 end		
 Observation phase->Notification: observation started		
 Observation phase->Notification: grace period started		
 Observation phase->Shutdown: limit reached		
 Shutdown->Notification: shut down initialized		
 ```		
 (translated by https://www.websequencediagrams.com)

## Installation

### Shell Script
1. Copy shell script and configuration file to shared volume (e.g. `control`)an your NAS. Remember the path to the shell script (e.g. `/volume1/control/syno-autoshutdown/`)
2. Rename the default configuration file to autoshutdown.conf or autoshutdown-(hostname).conf where (hostname) is the host name of your NAS. This is helpful if you have multiple NAS where you want to share files but separate configurations.
3. Proceed with scheduler configuration.

### Task (Scheduler)
(here: Synology DSM 6.x)
1. Login to NAS.
2. Define a new scheduled task at `system start` up to execute these commands

![autoshutdown_start_1](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/autoshutdown_start_1.png)

![autoshutdown_start_2](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/autoshutdown_start_2.png)
```
chmod 775 /volume1/control/syno-autoshutdown/autoshutdown.sh
/volume1/control/syno-autoshutdown/autoshutdown.sh
```
You must run this task/script as root, as some commands are not allowed as users. The task must also be defined to start at boot time so that the execution of the script can be ensured.

3. Define a second task to be started manually. This task help to deaktivate the shell script if you don't want to be interruped by a system shutdown (e.g. partition cleanup/repair if no client system is online)

![autoshutdown_start_1](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/autoshutdown_stop_1.png)

![autoshutdown_start_1](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/autoshutdown_stop_2.png)

```
chmod 775 /volume1/control/syno-autoshutdown/autoshutdown_killall.sh
/volume1/control/syno-autoshutdown/autoshutdown_killall.sh
```

The script must also be run as root, but the execution can be set to inactive (and thus manual). This task is only used to temporarily terminate a previously executed script or several instances of the script. If the autoshutdown script should be started again, the NAS does not have to be restarted, but the first task can be executed. 

4. Reboot NAS or start first created task manually.
5. Done ;)

### IFTTT (Notification) (optional)

1. Create an account with IFTTT (ifttt.com)
2. Log on to IFTTT at the backend
3. Click profile image and run "create" in menus
4. Define the "if" statement
5. Search for and select "webhooks"
6. Select "receive a web request"
7. Name your event (e.g. `syno_event`)
8. Define the "that" statement
9. Search for and select "notifications"
10. Select "send a notification from the IFTTT app"
11. Define the message `{{Value1}} (occurred {{OccurredAt}})`
12. Click "create action"
13. Define magic key to config file (IFTTT_KEY) *)
14. Define name of event (see 7.) to config file (IFTTT_EVENT)
15. Done.

![ifttt_maker_1](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/ifttt_maker_1.png)

*) Your magic key is viewable via ifttt.com -> profile -> my services -> webhooks -> settings -> URL

### Webserver (shutdown)

```
IMPORTANT NOTE:

The web server only uses security by obfuscation and no secure protection procedure against unauthorized calls. The use of this component must be evaluated individually. The module was designed to provide the functions as easily and quickly as possible via mobile end devices.
```

In addition to the bash script, a python script is provided, which optionally starts a web service that allows the user to shut down the NAS system immediately via HTTP request.

When the web server is started, a unique UUID is generated which can be used to control the web server. If the correct URL can be called by the user, the server is immediately shut down by calling another (confirmation) link.

The URL is protected by the following features by unintentional or deliberate calls:

- Free choice of the external and internal port on which the server listens
- Free choice of the component of the URL that is to be used for the shutdown
- Creation of a new and unique UUID at each start of the web server

Example of a link:
```
http://<ip>:48080/33ff4f76-c00b-42b9-9c08-d303aba64c2a/shutdown
```

Calling up the website allows a further confirmation of the shutdown:
![autoshutdown_webserver_execute](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/autoshutdown_webserver_execute.png)

If the button shown in the picture is confirmed, the system will shut down immediately.

THE WEBSERVER HAS TO BE ACTIVED BY SETTING CONFIG VALUE     WEBSERVER_SHUTDOWN_ACTIVE=1     !

### Alexa speech commands

The web server has been supplemented by a magic key and magic word. With the help of these two very individual details, the web service can be controlled via a voice command and a Werrequest without prior consultation.

These data have been additionally integrated to enable static data, so that the security of the dynamic keys for normal access can be maintained. 

Two factors are required for a successful call: the magic key, which is generated automatically if it is not already specified. And also a magic word, which can be freely assigned by the user. Both specifications are combined and result in a unique path specification for the web server. If this path is called, the system shuts down immediately.  

To make this address callable via voice commands, the following steps are necessary (Alexa and IFTTT are examples):

1. Add an Alexa trigger (or an other speech trigger)
2. Select the Alexa-Webhooks action (https://ifttt.com/connect/maker_webhooks/amazon_alexa)
3. Select "Use Alexa with hook  automate" (https://ifttt.com/applets/342458p-use-alexa-with-hook-to-automate)
4. Name your trigger
5. Define phrase Alexa will listen to

![alexa_ifttt_1](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/alexa_ifttt_1.png)

6. Define the URL of the magic webrequest. The URL contains following information

```
http://<public ip or adress>:<public port>/<magic key>/<magic word>
```
Your public ip and port depends on your router configuration. Have a look at section `Webserver (shutdown)` for more details.

![alexa_ifttt_2](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/alexa_ifttt_2.png)

7. Make ist a GET request
8. And define it as text/plain request
  
![alexa_ifttt_3](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/alexa_ifttt_3.png)

9. Save & Done

The next time you ask Alexa "Alexa, trigger shutdown Synology" the device will be shut down.

## Placeholder variables

### Notifications

Placeholders can be specified for messages in the configuration file. The following placeholders are permitted:

```
#VALID_MARKER_SYSTEMS_LIST# : List of found marker systems
#MY_START_TIME# : Start date/time of script
#MY_HOSTNAME# : Hostname of system running this script
#MY_PRIMARY_IP# : IP address of host running this script
#RUNLOOP_COUNTER# : number of executed loops at all
#RUNLOOP_TIME# : time of executed loops at all (RUNLOOP_COUNTER*SLEEP_TIME)
#RUNLOOP_TIME_HUMAN# : time of executed loops at all in format d:h:m:s
#SYS_UPTIME_HUMAN# : time since NAS startup in format h:m:s
```

### Log filename

Placeholders can be specified for filename in the configuration file. The following placeholders are permitted:

```
#DATETIME# : sortable date/time format (YYYYMMDD-HHmmss)
#DATE# :  sortable date format (YYYYMMDD)
#TIME# :  sortable 24h time format (HHmmss)
```

## Other files

#### autoshutdown.hash

File containing the hash value of its own running configuration (*.config). This hash value is compared to the hash value of the saved configuration file. If the values differ, the configuration has been changed and the script reads the configuration again in the next cycle.

#### autoshutdown.pid

File that contains the process ID of the running instance of the script.

#### autoshutdown.pidhash

File containing the hash value of a running shell script. This hash value is compared to the hash value of the saved shell script. If the values differ, the shell script has been changed and the script must be restarted. The running instance is terminated in the next cycle.
