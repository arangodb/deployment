#
# This script is provided as-is, no warrenty is provided or implied.
# The author is NOT responsible for any damages or data loss that may occur through the use of this script.
#
# This function starts an ArangoDB cluster by just using docker
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
#   NRDBSERVERS      : is always set to the length of SERVERS_EXTERNAL if
#                      not specified
#   NRCOORDINATORS   : default: $NRDBSERVERS, can be less, at least 1
#   PORT_DBSERVER    : default: 8629
#   PORT_COORDINATOR : default: 8529
#   PORT_REPLICA     : default: 8630
#   DBSERVER_DATA    : default: "/home/$SSH_USER/dbserver"
#   COORDINATOR_DATA : default: "/home/$SSH_USER/coordinator"
#   DBSERVER_LOGS    : default: "/home/$SSH_USER/dbserver_logs"
#   COORDINATOR_LOGS : default: "/home/$SSH_USER/coordinator_logs"
#   REPLICA_DATA     : default: "/home/$SSH_USER/replica"
#   REPLICA_LOGS     : default: "/home/$SSH_USER/replica_logs"
#   AGENCY_DIR       : default: /home/$SSH_USER/agency"
#   DBSERVER_ARGS    : default: ""
#   COORDINATOR_ARGS : default: ""
#   REPLICA_ARGS     : default: ""
#   REPLICAS         : default : "", if non-empty, one asynchronous replica
#                      is started for each DBserver, it resides on the "next"
#                      machine

# There will be one DBserver on each machine and at most one coordinator.
# There will be one agency running on the first machine.
# Each DBserver uses /

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[i]} ${SSH_SUFFIX} docker run ...

startArangoDBClusterWithDocker() {

    DOCKER_IMAGE_NAME=m0ppers/arangodb:3.0

    # Two docker images are needed: 
    #  microbox/etcd for the agency and
    #  ${DOCKER_IMAGE_NAME} for
    #   - arangod
    #   - arangosh
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
    declare -a SERVERS_EXTERNAL_ARR=($SERVERS_EXTERNAL)
    echo SERVERS_EXTERNAL: ${SERVERS_EXTERNAL_ARR[*]}

    if [ -z "$SERVERS_INTERNAL" ] ; then
      declare -a SERVERS_INTERNAL_ARR=(${SERVERS_EXTERNAL_ARR[*]})
    else
      declare -a SERVERS_INTERNAL_ARR=($SERVERS_INTERNAL)
    fi
    echo SERVERS_INTERNAL: ${SERVERS_INTERNAL_ARR[*]}

    if [ -z "$NRDBSERVERS" ] ; then
        NRDBSERVERS=${#SERVERS_EXTERNAL_ARR[*]}
    fi
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

    if [ -z "$PORT_REPLICA" ] ; then
      PORT_REPLICA=8630
    fi
    echo PORT_REPLICA=$PORT_REPLICA

    i=$NRDBSERVERS
    if [ $i -ge ${#SERVERS_INTERNAL_ARR[*]} ] ; then
        i=0
    fi
    COORDINATOR_MACHINES="$i"
    FIRST_COORDINATOR=$i
    for j in `seq 1 $LASTCOORDINATOR` ; do
        i=`expr $i + 1`
        if [ $i -ge ${#SERVERS_INTERNAL_ARR[*]} ] ; then
            i=0
        fi
        COORDINATOR_MACHINES="$COORDINATOR_MACHINES $i"
    done
    echo COORDINATOR_MACHINES:$COORDINATOR_MACHINES
    echo FIRST_COORDINATOR: $FIRST_COORDINATOR

    if [ -z "$DBSERVER_DATA" ] ; then
      DBSERVER_DATA=/home/$SSH_USER/dbserver
    fi
    echo DBSERVER_DATA=$DBSERVER_DATA

    if [ -z "$DBSERVER_LOGS" ] ; then
      DBSERVER_LOGS=/home/$SSH_USER/dbserver_logs
    fi
    echo DBSERVER_LOGS=$DBSERVER_LOGS

    if [ -z "$REPLICA_DATA" ] ; then
      REPLICA_DATA=/home/$SSH_USER/replica
    fi
    echo REPLICA_DATA=$REPLICA_DATA

    if [ -z "$REPLICA_LOGS" ] ; then
      REPLICA_LOGS=/home/$SSH_USER/replica_logs
    fi
    echo REPLICA_LOGS=$REPLICA_LOGS

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

    echo Creating directories on servers. This may take some time. Please wait.
    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX mkdir $AGENCY_DIR >/dev/null 2>&1 &
    for i in `seq 0 $LASTDBSERVER` ; do
        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX mkdir $DBSERVER_DATA $DBSERVER_LOGS >/dev/null 2>&1 &
    done
    for i in $COORDINATOR_MACHINES ; do
        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX mkdir $COORDINATOR_DATA $COORDINATOR_LOGS >/dev/null 2>&1 &
    done
    if [ ! -z "$REPLICAS" ] ; then
        for i in `seq 0 $LASTDBSERVER` ; do
            j=`expr $i + 1`
            if [ $j -gt $LASTDBSERVER ] ; then
                j=0
            fi
            $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$j]} $SSH_SUFFIX mkdir $REPLICA_DATA $REPLICA_LOGS >/dev/null 2>&1 &
        done
    fi

    wait

    echo Starting agency...
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true -e ARANGO_NO_AUTH=1 -p 4001:8529 --name=agency -v $AGENCY_DIR:/var/lib/arangodb3 ${DOCKER_IMAGE_NAME}  --server.authentication false --agency.id 0 --agency.size 1 --javascript.v8-contexts 2"
    do
        echo "Error in remote docker run, retrying..."
    done

    sleep 1

    start_dbserver () {
        i=$1
        echo Starting DBserver on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
            docker run -p $PORT_DBSERVER:8529 --detach=true -e ARANGO_NO_AUTH=1 -v $DBSERVER_DATA:/var/lib/arangodb3 \
             --name=dbserver$PORT_DBSERVER ${DOCKER_IMAGE_NAME} \
              arangod --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
              --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
              --cluster.my-local-info dbserver:${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
              --cluster.my-role PRIMARY \
              --scheduler.threads 3 \
              --server.threads 5 \
              --javascript.v8-contexts 6 \
              $DBSERVER_ARGS
        do
            echo "Error in remote docker run, retrying..."
        done
    }

    start_coordinator () {
        i=$1
        echo Starting Coordinator on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
            docker run -p $PORT_COORDINATOR:8529 --detach=true -e ARANGO_NO_AUTH=1 -v $COORDINATOR_DATA:/var/lib/arangodb3 \
                --name=coordinator$PORT_COORDINATOR \
                ${DOCKER_IMAGE_NAME} \
              arangod --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
               --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_COORDINATOR \
               --cluster.my-local-info \
                         coordinator:${SERVERS_INTERNAL_ARR[$i]}:$PORT_COORDINATOR \
               --cluster.my-role COORDINATOR \
               --scheduler.threads 4 \
               --javascript.v8-contexts 11 \
               --server.threads 10 \
               $COORDINATOR_ARGS
        do
            echo "Error in remote docker run, retrying..."
        done
    }

    for i in `seq 0 $LASTDBSERVER` ; do
        start_dbserver $i &
    done

    wait

    for i in $COORDINATOR_MACHINES ; do
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
    
    DBSERVER_IDS=()
    for i in `seq 0 $LASTDBSERVER` ; do
        testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER
        DBSERVER_IDS[$i]=$(curl http://"${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER"/_admin/server/id)
    done

    for i in $COORDINATOR_MACHINES ; do
        testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR
    done
    
    if [ ! -z "$REPLICAS" ] ; then
        start_replica () {
            i=$1
            j=`expr $i + 1`
            ID="Secondary$j"
            if [ $j -gt $LASTDBSERVER ] ; then
                j=0
            fi
            echo Starting asynchronous replica for
            echo "  ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER on ${SERVERS_EXTERNAL_ARR[$j]}:$PORT_REPLICA"
            
            while true; do
              curl -f -X PUT --data "{\"primary\": \"${DBSERVER_IDS[$i]}\", \"oldSecondary\": \"none\", \"newSecondary\": \"${ID}\"}" -H "Content-Type: application/json" "${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"/_admin/cluster/replaceSecondary
              if [ "$?" == "0" ]; then
                break
              fi
              echo "Failed registering secondary...Retrying..."
              sleep 1
            done

            until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$j]} $SSH_SUFFIX \
                docker run -p 8529:$PORT_REPLICA --detach=true -e ARANGO_NO_AUTH=1 -v $REPLICA_DATA:/var/lib/arangodb3 \
                 --name=replica$PORT_REPLICA ${DOCKER_IMAGE_NAME} \
                  arangod \
                  --cluster.my-id "$ID" \
                  --cluster.my-role SECONDARY \
                  --scheduler.threads 3 \
                  --server.threads 5 \
                  --javascript.v8-contexts 6 \
                  $REPLICA_ARGS
            do
                echo "Error in remote docker run, retrying..."
            done
        }

        for i in `seq 0 $LASTDBSERVER` ; do
            start_replica $i
        done

        echo Waiting 10 seconds till replicas are up and running...
        sleep 10
    fi

    echo ""
    echo "=============================================================================="
    echo "Done, your cluster is ready."
    echo "=============================================================================="
    echo ""
    echo "Frontends available at:"
    for i in $COORDINATOR_MACHINES ; do
        echo "   http://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"
    done
    echo ""
    echo "Access with docker, using arangosh:"
    for i in $COORDINATOR_MACHINES ; do
        echo "   docker run -it --rm --net=host ${DOCKER_IMAGE_NAME} arangosh --server.endpoint tcp://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"
    done
    echo ""
}

