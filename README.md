# Syology Autoshutdown

A simple shell script to shutdown a Synology NAS if no authorized client is online. The main purpose of this script is to reduce power consumption. 

## Purpose

The NAS can be used to store media content. If you want to access them, the system is switched on manually or by wake-on-lan. The system is in operation during this time. But what happens if the client is no longer online? The NAS continues to run and goes into standby - but it usually continues to consume power. 
This script helps to turn off the system completely and thus save power; since media access usually only has a comparatively short duration. The next time the system is accessed, it is started again manually or by wake-on-lan.

The script also has the advantage that no inflated packages need to be installed on the NAS that could compromise the security or stability of the system. If you want to keep the system as clean as possible and know which features are running on the system, open source and a shell script is just what you need :)

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

## Prerequisites
- NAS (Synology with Busy Box)
- own volume (recommended)
- SSH access (recommended)
- Scheduler (e.g. Cron) with possibility to execute shell scripts

## Presumption
- Installation on a Synology with DSM 6.x

## Installation

### Shell Script

### Task (Scheduler)

### IFTTT (Notification)

#### Initialization

#### (temporary) Deactivation
