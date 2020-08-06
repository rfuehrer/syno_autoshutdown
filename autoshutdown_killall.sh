#!/bin/bash

SEARCH_KILL="autoshutdown.sh"
echo "Searching for '$SEARCH_KILL' processes..."
for p in `ps -ef|grep $SEARCH_KILL|grep -v grep| awk '{print $2}'`; do
   echo "Killing '$SEARCH_KILL' with PID $p..."
   kill -9 $p
done

SEARCH_KILL="autoshutdown_webserver.py"
echo "Searching for '$SEARCH_KILL' processes..."
for p in `ps -ef|grep $SEARCH_KILL|grep -v grep| awk '{print $2}'`; do
   echo "Killing '$SEARCH_KILL' with PID $p..."
   kill -9 $p
done