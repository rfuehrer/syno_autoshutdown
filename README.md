# Synology Autoshutdown

A simple shell script to shutdown a Synology NAS if no authorized client is online. The main purpose of this script is to reduce power consumption. 

## Purpose

The NAS can be used to store media content. If you want to access them, the system is switched on manually or by wake-on-lan. The system is in operation during this time. But what happens if the client is no longer online? The NAS continues to run and goes into standby - but it usually continues to consume power. 
This script helps to turn off the system completely and thus save power; since media access usually only has a comparatively short duration. The next time the system is accessed, it is started again manually or by wake-on-lan.

The script also has the advantage that no inflated packages need to be installed on the NAS that could compromise the security or stability of the system. If you want to keep the system as clean as possible and know which features are running on the system, open source and a shell script is just what you need :)

## Basic mechanism
At definable intervals, all systems of the current network segment (e.g. 10.0.0.x) are checked whether they are reachable. If a system could be detected, this is compared with the list of systems that were defined to avoid a shutdown. If no system could be found, the system continues to attempt to find systems for a defined period of time. If no systems are found during this time, the system is shut down. A named system found resets this check.

## Functions
- Bash Script
- Use of simple functions from Busy Box
- Connection to IFTTT (optional)
- logging
- Automatic initialization when configuration is changed
- automatic restart of the script on code change
- warning times
- Support of beep output to the internal NAS loudspeaker

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
- NAS (Synology with Busy Box)
- own volume (recommended)
- SSH access (recommended)
- Scheduler (e.g. Cron) with possibility to execute shell scripts

## Presumption
- Installation on a Synology with DSM 6.x

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
kill `pidof autoshutdown.sh`
```

The script must also be run as root, but the execution can be set to inactive (and thus manual). This task is only used to temporarily terminate a previously executed script or several instances of the script. If the autoshutdown script should be started again, the NAS does not have to be restarted, but the first task can be executed. 

4. Reboot NAS or start first created task manually.
5. Done ;)

### IFTTT (Notification)

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
13. Done.

![ifttt_maker_1](https://github.com/rfuehrer/syno_autoshutdown/blob/master/images/ifttt_maker_1.png)

## Other files

#### autoshutdown.hash

File containing the hash value of its own running configuration (*.config). This hash value is compared to the hash value of the saved configuration file. If the values differ, the configuration has been changed and the script reads the configuration again in the next cycle.

#### autoshutdown.pid

File that contains the process ID of the running instance of the script.

#### autoshutdown.pidhash

File containing the hash value of a running shell script. This hash value is compared to the hash value of the saved shell script. If the values differ, the shell script has been changed and the script must be restarted. The running instance is terminated in the next cycle.
