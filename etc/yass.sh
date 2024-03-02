#!/bin/bash
# Temporary RC script for yass.

  # case statement to start/stop.
  case "$1" in
    start) /usr/local/yass/bin/yass -t > /dev/null
           /usr/local/yass/bin/yass -d > /dev/null
           echo "yass";
           ;;
    stop)  /usr/local/yass/bin/yass -t > /dev/null
           echo "yass";
           ;;
    *)     echo "Usage: $0 {start|stop}" && exit 1 ;;
  esac
  exit 0;
