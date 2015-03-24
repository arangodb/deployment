#!/bin/bash

# This starts a local ArangoDB cluster by just using docker
#
# Usage: the following environment variables are used:
#   NRDBSERVERS    : number of DBservers to start
#   NRCOORDINATORS : number of coordinators to start
#
# Two docker images are needed: 
#  microbox/etcd for the agency and
#  neunhoef/arangodb_cluster for
#   - arangod
#   - arnagosh
#   - some helper scripts

# The directory /tmp/cluster on the local machine is recursively
# erased and holds all data and logs for the whole cluster.

# To stop the cluster simply stop and remove the containers with the
# names
#   - agency
#   - discovery
#   - coordinator<Port>
#   - dbserver<Port>

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

if [ -d /tmp/cluster ] ; then
  echo Please delete directoy /tmp/cluster recursively! Giving up.
  exit 1
fi

mkdir /tmp/cluster
mkdir /tmp/cluster/etcd
mkdir /tmp/cluster/discovery

echo Starting agency...
docker run --detach=true -p 4001:4001 --name=agency -v /tmp/cluster/etcd:/data microbox/etcd:latest etcd -name agency > /tmp/cluster/etcd.id

sleep 1
echo Initializing agency...
docker run -it --link=agency:agency --rm neunhoef/arangodb_cluster arangosh --javascript.execute /scripts/init_agency.js > /tmp/cluster/init_agency.log
echo Starting discovery...
docker run --detach=true --link=agency:agency -v /tmp/cluster/discovery:/discovery --name discovery neunhoef/arangodb_cluster arangosh --javascript.execute scripts/discover.js > /tmp/cluster/discovery.id

start() {
    TYPE=$1
    PORT=$2
    mkdir /tmp/cluster/data$PORT
    echo Starting $TYPE on port $PORT
    docker run --detach=true -v /tmp/cluster/data$PORT:/data \
           -v /tmp/cluster:/log --net=host --name=$TYPE$PORT \
           neunhoef/arangodb_cluster \
        arangod --database.directory /data \
                --cluster.agency-endpoint tcp://127.0.0.1:4001 \
                --cluster.my-address tcp://127.0.0.1:$PORT \
                --server.endpoint tcp://127.0.0.1:$PORT \
                --cluster.my-local-info $TYPE:127.0.0.1:$PORT \
                --log.file /log/$PORT.log > /tmp/cluster/server$PORT.id
}

PORTTOPDB=`expr 8629 + $NRDBSERVERS - 1`
for p in `seq 8629 $PORTTOPDB` ; do
    start dbserver $p
done
PORTTOPCO=`expr 8530 + $NRCOORDINATORS - 1`
for p in `seq 8530 $PORTTOPCO` ; do
    start coordinator $p
done

echo Waiting for cluster to come up...

testServer() {
    PORT=$1
    while true ; do
        sleep 1
        curl -s -X GET "http://127.0.0.1:$PORT/_api/version" > /dev/null 2>&1
        if [ "$?" != "0" ] ; then
            echo Server on port $PORT does not answer yet.
        else
            echo Server on port $PORT is ready for business.
            break
        fi
    done
}

testServer $PORTTOPCO
if [ "8530" != "$PORTTOPCO" ] ; then
    testServer 8530
fi

echo Bootstrapping DBServers...
for p in `seq 8629 $PORTTOPDB` ; do
    curl -s -X POST "http://127.0.0.1:$p/_admin/cluster/bootstrapDbServers" \
         -d '{"isRelaunch":false}' >> /tmp/cluster/DBServer.boot.log 2>&1
done

echo Running DB upgrade on cluster...
curl -s -X POST "http://127.0.0.1:8530/_admin/cluster/upgradeClusterDatabase" \
     -d '{"isRelaunch":false}' >> /tmp/cluster/DBUpgrade.log 2>&1

echo Bootstrapping Coordinators...
for p in `seq 8530 $PORTTOPCO` ; do
    curl -s -X POST "http://127.0.0.1:8530/_admin/cluster/bootstrapCoordinator" \
         -d '{"isRelaunch":false}' >> /tmp/cluster/Coordinator.boot.log 2>&1
done

echo Done, your cluster is ready at
for p in `seq 8530 $PORTTOPCO` ; do
    echo "   docker run -it --rm --net=host neunhoef/arangodb_cluster arangosh --server.endpoint tcp://127.0.0.1:$p"
done

