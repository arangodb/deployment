#!/bin/bash

# This removes a local ArangoDB cluster by just using docker
#
# Usage: the following environment variables are used:
#   NRDBSERVERS    : number of DBservers to start
#   NRCOORDINATORS : number of coordinators to start

NRDBSERVERS=$1
if [ "$NRDBSERVERS" == "" ] ; then
    NRDBSERVERS=2
fi
echo Number of DBServers: $NRDBSERVERS
NRCOORDINATORS=$2
if [ "$NRCOORDINATORS" == "" ] ; then
    NRCOORDINATORS=1
fi
echo Number of Coordinators: $NRCOORDINATORS

stop() {
    TYPE=$1
    PORT=$2
    echo Stopping $TYPE on port $PORT
    docker rm -f $TYPE$PORT 2>/dev/null &
}

PORTTOPCO=`expr 8530 + $NRCOORDINATORS - 1`
for p in `seq 8530 $PORTTOPCO` ; do
    stop coordinator $p
done

wait

PORTTOPDB=`expr 8629 + $NRDBSERVERS - 1`
for p in `seq 8629 $PORTTOPDB` ; do
    stop dbserver $p
done

wait

echo Removing discovery...
docker rm -f discovery

echo Removing agency...
docker rm -f agency
