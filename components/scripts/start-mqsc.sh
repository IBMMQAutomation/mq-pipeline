#!/bin/bash
#
# A simple MVP script that will run MQSC against a queue manager.
cksum=""

# Outer loop that keeps the MQ service running
while true; do

   tmpCksum=`cksum /dyn-mq-config-mqsc/dynamic.mqsc | cut -d" " -f1`

   if (( tmpCksum != cksum ))
   then
      cksum=$tmpCksum
      echo "Applying MQSC"
      eval "echo \"$(cat /dyn-mq-config-mqsc/dynamic.mqsc)\"" | runmqsc
   else
      sleep 3
   fi

done
