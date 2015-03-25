#!/bin/bash

# This removes an ArangoDB cluster by removing the docker containers
#
# Prerequisites:
# The following environment variables are used:
#   SERVERS_EXTERNAL : list of IP addresses or hostnames, separated by 
#                      whitespace, this must be the network interfaces
#                      that are reachable from the outside
#   SERVERS_INTERNAL : list of IP addresses or hostnames, sep by whitespace
#                      must be same length as SERVERS_EXTERNAL
#                      this must be the corresponding network interfaces 
#                      that are reachable from the outside, can be the same
#   SSH_CMD          : command to use for ssh connection [default "ssh"]
#   SSH_USER         : user name on remote machine [default "core"]
#   SSH_SUFFIX       : suffix for ssh command [default ""].
#   NRDBSERVERS      : is always set to the length of SERVERS_EXTERNAL
#   NRCOORDINATORS   : default: $NRDBSERVERS, can be less, at least 1
#   PORT_DBSERVER    : default: 8629
#   PORT_COORDINATOR : default: 8529

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} ${SSH_USER}@${SERVERS_EXTERNAL[i]} ${SSH_SUFFIX} docker ...

if [ -z "$SERVERS_EXTERNAL" ] ; then
  echo Need SERVERS_EXTERNAL environment vairable
  exit 1
fi
declare -a SERVERS_EXTERNAL=($SERVERS_EXTERNAL)

NRDBSERVERS=${#SERVERS_EXTERNAL[*]}
LASTDBSERVER=`expr $NRDBSERVERS - 1`

echo Number of DBServers: $NRDBSERVERS
NRCOORDINATORS=$2
if [ -z "$NRCOORDINATORS" ] ; then
    NRCOORDINATORS=$NRDBSERVERS
fi
LASTCOORDINATOR=`expr $NRCOORDINATORS - 1`
echo Number of Coordinators: $NRCOORDINATORS

if [ -z "$SSH_CMD" ] ; then
  SSH_CMD=ssh
fi
echo SSH_CMD=$SSH_CMD

if [ -z "$SSH_USER" ] ; then
  SSH_USER=core
fi
echo SSH_USER=$SSH_USER

if [ -z "$PORT_DBSERVER" ] ; then
  PORT_DBSERVER=8629
fi
echo PORT_DBSERVER=$PORT_DBSERVER

if [ -z "$PORT_COORDINATOR" ] ; then
  PORT_COORDINATOR=8529
fi
echo PORT_COORDINATOR=$PORT_COORDINATOR

stop_dbserver () {
    i=$1
    echo Removing DBserver on ${SERVERS_EXTERNAL[$i]}:$PORT_DBSERVER

    $SSH_CMD ${SSH_USER}@${SERVERS_EXTERNAL[$i]} $SSH_SUFFIX \
             docker rm -f dbserver$PORT_DBSERVER >/dev/null
}

stop_coordinator () {
    i=$1
    echo Removing Coordinator on ${SERVERS_EXTERNAL[$i]}:$PORT_COORDINATOR

    $SSH_CMD ${SSH_USER}@${SERVERS_EXTERNAL[$i]} $SSH_SUFFIX \
             docker rm -f coordinator$PORT_COORDINATOR >/dev/null
}

for i in `seq 0 $LASTCOORDINATOR` ; do
    stop_coordinator $i &
done

wait

for i in `seq 0 $LASTDBSERVER` ; do
    stop_dbserver $i &
done

wait

echo Removing discovery

$SSH_CMD ${SSH_USER}@${SERVERS_EXTERNAL[0]} $SSH_SUFFIX  docker rm -f discovery > /dev/null &

echo Removing agency

$SSH_CMD ${SSH_USER}@${SERVERS_EXTERNAL[0]} $SSH_SUFFIX docker rm -f agency >/dev/null &

wait
