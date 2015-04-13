#!/bin/bash

# This starts a ArangoDB cluster by just using docker
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
#   SSH_ARGS         : arguments to SSH_CMD, will be expanded in
#                      quotes [default: "-oStrictHostKeyChecking no"]
#   SSH_USER         : user name on remote machine [default "core"]
#   SSH_SUFFIX       : suffix for ssh command [default ""].
#   NRDBSERVERS      : is always set to the length of SERVERS_EXTERNAL
#   NRCOORDINATORS   : default: $NRDBSERVERS, can be less, at least 1
#   PORT_DBSERVER    : default: 8629
#   PORT_COORDINATOR : default: 8529
#   DBSERVER_DATA    : default: "/home/$SSH_USER/dbserver"
#   COORDINATOR_DATA : default: "/home/$SSH_USER/coordinator"
#   DBSERVER_LOGS    : default: "/home/$SSH_USER/dbserver_logs"
#   COORDINATOR_LOGS : default: "/home/$SSH_USER/coordinator_logs"
#   AGENCY_DIR       : default: /home/$SSH_USER/agency"

# There will be one DBserver on each machine and at most one coordinator.
# There will be one agency running on the first machine.
# Each DBserver uses /

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[i]} ${SSH_SUFFIX} docker run ...

DOCKER_IMAGE_NAME=neunhoef/arangodb_cluster:latest

# Two docker images are needed: 
#  microbox/etcd for the agency and
#  ${DOCKER_IMAGE_NAME} for
#   - arangod
#   - arnagosh
#   - some helper scripts

# To stop the cluster simply stop and remove the containers with the
# names
#   - agency
#   - discovery
#   - coordinator
#   - dbserver
# on all machines.

set +u

if [ -z "$SERVERS_EXTERNAL" ] ; then
  echo Need SERVERS_EXTERNAL environment variable
  exit 1
fi
declare -a SERVERS_EXTERNAL=($SERVERS_EXTERNAL)
echo SERVERS_EXTERNAL: ${SERVERS_EXTERNAL[*]}

if [ -z "$SERVERS_INTERNAL" ] ; then
  declare -a SERVERS_INTERNAL=(${SERVERS_EXTERNAL[*]})
else
  declare -a SERVERS_INTERNAL=($SERVERS_INTERNAL)
fi
echo SERVERS_INTERNAL: ${SERVERS_INTERNAL[*]}

NRDBSERVERS=${#SERVERS_EXTERNAL[*]}
LASTDBSERVER=`expr $NRDBSERVERS - 1`

echo Number of DBServers: $NRDBSERVERS
if [ -z "$NRCOORDINATORS" ] ; then
    NRCOORDINATORS=$NRDBSERVERS
fi
LASTCOORDINATOR=`expr $NRCOORDINATORS - 1`
echo Number of Coordinators: $NRCOORDINATORS

if [ -z "$SSH_CMD" ] ; then
  SSH_CMD=ssh
fi
echo SSH_CMD=$SSH_CMD

if [ -z "$SSH_ARGS" ] ; then
  SSH_ARGS="-oStrictHostKeyChecking no"
fi
echo SSH_ARGS=$SSH_ARGS

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

if [ -z "$DBSERVER_DATA" ] ; then
  DBSERVER_DATA=/home/$SSH_USER/dbserver
fi
echo DBSERVER_DATA=$DBSERVER_DATA

if [ -z "$DBSERVER_LOGS" ] ; then
  DBSERVER_LOGS=/home/$SSH_USER/dbserver_logs
fi
echo DBSERVER_LOGS=$DBSERVER_LOGS

if [ -z "$AGENCY_DIR" ] ; then
  AGENCY_DIR=/home/$SSH_USER/agency
fi
echo AGENCY_DIR=$AGENCY_DIR

if [ -z "$COORDINATOR_DATA" ] ; then
  COORDINATOR_DATA=/home/$SSH_USER/coordinator_data
fi
echo COORDINATOR_DATA=$COORDINATOR_DATA

if [ -z "$COORDINATOR_LOGS" ] ; then
  COORDINATOR_LOGS=/home/$SSH_USER/coordinator_logs
fi
echo COORDINATOR_LOGS=$COORDINATOR_LOGS

echo Creating directories on servers
$SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[0]} $SSH_SUFFIX mkdir $AGENCY_DIR >/dev/null 2>&1 &
for i in `seq 0 $LASTDBSERVER` ; do
  $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[$i]} $SSH_SUFFIX mkdir $DBSERVER_DATA $DBSERVER_LOGS >/dev/null 2>&1 &
done
for i in `seq 0 $LASTCOORDINATOR` ; do
  $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[$i]} $SSH_SUFFIX mkdir $COORDINATOR_DATA $COORDINATOR_LOGS >/dev/null 2>&1 &
done

wait

echo Starting agency...
$SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[0]} $SSH_SUFFIX "docker run --detach=true -p 4001:4001 --name=agency -v $AGENCY_DIR:/data microbox/etcd:latest etcd -name agency >/home/$SSH_USER/agency.log"

sleep 1
echo Initializing agency...
$SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[0]} $SSH_SUFFIX "docker run --link=agency:agency --rm ${DOCKER_IMAGE_NAME} arangosh --javascript.execute /scripts/init_agency.js > /home/$SSH_USER/init_agency.log"
echo Starting discovery...
$SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[0]} $SSH_SUFFIX "docker run --detach=true --link=agency:agency --name discovery ${DOCKER_IMAGE_NAME} arangosh --javascript.execute scripts/discover.js > /home/$SSH_USER/discovery.log"

start_dbserver () {
    i=$1
    echo Starting DBserver on ${SERVERS_EXTERNAL[$i]}:$PORT_DBSERVER

    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[$i]} $SSH_SUFFIX \
    docker run --detach=true -v $DBSERVER_DATA:/data \
     -v $DBSERVER_LOGS:/logs --net=host \
     --name=dbserver$PORT_DBSERVER ${DOCKER_IMAGE_NAME} \
      arangod --database.directory /data \
      --cluster.agency-endpoint tcp://${SERVERS_INTERNAL[0]}:4001 \
      --cluster.my-address tcp://${SERVERS_INTERNAL[$i]}:$PORT_DBSERVER \
      --server.endpoint tcp://0.0.0.0:$PORT_DBSERVER \
      --cluster.my-local-info dbserver:${SERVERS_INTERNAL[$i]}:$PORT_DBSERVER \
      --log.file /logs/$PORT_DBSERVER.log >/dev/null
}

start_coordinator () {
    i=$1
    echo Starting Coordinator on ${SERVERS_EXTERNAL[$i]}:$PORT_COORDINATOR

    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL[$i]} $SSH_SUFFIX \
     docker run --detach=true -v $COORDINATOR_DATA:/data \
        -v $COORDINATOR_LOGS:/logs --net=host \
        --name=coordinator$PORT_COORDINATOR \
        ${DOCKER_IMAGE_NAME} \
      arangod --database.directory /data \
       --cluster.agency-endpoint tcp://${SERVERS_INTERNAL[0]}:4001 \
       --cluster.my-address tcp://${SERVERS_INTERNAL[$i]}:$PORT_COORDINATOR \
       --server.endpoint tcp://0.0.0.0:$PORT_COORDINATOR \
       --cluster.my-local-info \
                 coordinator:${SERVERS_INTERNAL[$i]}:$PORT_COORDINATOR \
       --log.file /logs/$PORT_COORDINATOR.log >/dev/null
}

for i in `seq 0 $LASTDBSERVER` ; do
    start_dbserver $i &
done

wait

for i in `seq 0 $LASTCOORDINATOR` ; do
    start_coordinator $i &
done

wait 

echo Waiting for cluster to come up...

testServer() {
    ENDPOINT=$1
    while true ; do
        sleep 1
        curl -s -X GET "http://$ENDPOINT/_api/version" > /dev/null 2>&1
        if [ "$?" != "0" ] ; then
            echo Server at $ENDPOINT does not answer yet.
        else
            echo Server at $ENDPOINT is ready for business.
            break
        fi
    done
}

#for i in `seq 0 $LASTDBSERVER` ; do
#    testServer ${SERVERS_EXTERNAL[$i]}:$PORT_DBSERVER
#done

for i in `seq 0 $LASTCOORDINATOR` ; do
    testServer ${SERVERS_EXTERNAL[$i]}:$PORT_COORDINATOR
done

echo Bootstrapping DBServers...
curl -s -X POST "http://${SERVERS_EXTERNAL[0]}:$PORT_COORDINATOR/_admin/cluster/bootstrapDbServers" \
     -d '{"isRelaunch":false}' >/dev/null 2>&1

echo Running DB upgrade on cluster...
curl -s -X POST "http://${SERVERS_EXTERNAL[0]}:$PORT_COORDINATOR/_admin/cluster/upgradeClusterDatabase" \
     -d '{"isRelaunch":false}' >/dev/null 2>&1

echo Bootstrapping Coordinators...
for i in `seq 0 $LASTCOORDINATOR` ; do
    echo Doing ${SERVERS_EXTERNAL[$i]}:$PORT_COORDINATOR
    curl -s -X POST "http://${SERVERS_EXTERNAL[$i]}:$PORT_COORDINATOR/_admin/cluster/bootstrapCoordinator" \
         -d '{"isRelaunch":false}' >/dev/null 2>&1 &
done

wait

echo Done, your cluster is ready at
for i in `seq 0 $LASTCOORDINATOR` ; do
    echo "   docker run -it --rm --net=host ${DOCKER_IMAGE_NAME} arangosh --server.endpoint tcp://${SERVERS_EXTERNAL[$i]}:$PORT_COORDINATOR"
done

