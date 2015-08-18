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
#   ZOOKEEPER_DATA   : default: "/home/$SSH_USER/zookeeper"
#   ZOOKEEPER_LOGS   : default: "/home/$SSH_USER/zookeeper_logs"
#   MASTER_DATA      : default: "/home/$SSH_USER/mesos_master"
#   MASTER_LOGS      : default: "/home/$SSH_USER/mesos_master_logs"
#   SLAVE_DATA       : default: "/home/$SSH_USER/mesos_slave"
#   SLAVE_LOGS       : default: "/home/$SSH_USER/mesos_slave_logs"
#   MARATHON_DATA    : default: "/home/$SSH_USER/marathon"
#   MARATHON_LOGS    : default: "/home/$SSH_USER/marathon-logs"
#   ZOOKEEPER_ARGS   : default: ""
#   MASTER_ARGS      : default: ""
#   SLAVE_ARGS       : default: ""
#   MARATHON_ARGS    : default: ""

# There will be one Zookeeper instance running on the first machine.
# There will be one Mesos master instance running on the first machine.
# There will be one Mesos slave on each machine.
# There will be one instance of Marathon on the first machine.

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[i]} ${SSH_SUFFIX} docker run ...

startMesosClusterWithDocker() {

    ZOOKEEPER_IMAGE_NAME=neunhoef/zookeeper
    MESOS_IMAGE_NAME=neunhoef/mesosphere-docker-mesos-master
    MARATHON_IMAGE_NAME=neunhoef/mesosphere-docker-marathon

    # Three docker images are needed: 
    #  ${ZOOKEEPER_IMAGE_NAME} for zookeeper, and
    #  ${MESOS_IMAGE_NAME} for Mesos master and slave
    #  ${MARATHON_IMAGE_NAME} for Marathon

    # To stop the cluster simply stop and remove the containers with the
    # names
    #   - zookeeper
    #   - mesos_master
    #   - mesos_slaves (all of them)
    #   - marathon
    # on all machines.

    set +u

    if [ -z "$SERVERS_EXTERNAL" ] ; then
      echo Need SERVERS_EXTERNAL environment variable
      exit 1
    fi
    declare -a SERVERS_EXTERNAL_ARR=($SERVERS_EXTERNAL)
    echo SERVERS_EXTERNAL: ${SERVERS_EXTERNAL_ARR[*]}
    NRSERVERS=${#SERVERS_EXTERNAL_ARR[*]}
    echo NRSERVERS=${NRSERVERS}
    LASTSERVER=`expr $NRSERVERS - 1`
    echo LASTSERVER=${LASTSERVER}

    if [ -z "$SERVERS_INTERNAL" ] ; then
      declare -a SERVERS_INTERNAL_ARR=(${SERVERS_EXTERNAL_ARR[*]})
    else
      declare -a SERVERS_INTERNAL_ARR=($SERVERS_INTERNAL)
    fi
    echo SERVERS_INTERNAL: ${SERVERS_INTERNAL_ARR[*]}

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

    if [ -z "$ZOOKEEPER_DATA" ] ; then
      ZOOKEEPER_DATA=/home/$SSH_USER/zookeeper
    fi
    echo ZOOKEEPER_DATA=$ZOOKEEPER_DATA

    if [ -z "$ZOOKEEPER_LOGS" ] ; then
      ZOOKEEPER_LOGS=/home/$SSH_USER/zookeeper_logs
    fi
    echo ZOOKEEPER_LOGS=$ZOOKEEPER_LOGS

    if [ -z "$MASTER_DATA" ] ; then
      MASTER_DATA=/home/$SSH_USER/mesos_master
    fi
    echo MASTER_DATA=$MASTER_DATA

    if [ -z "$MASTER_LOGS" ] ; then
      MASTER_LOGS=/home/$SSH_USER/mesos_master_logs
    fi
    echo MASTER_LOGS=$MASTER_LOGS

    if [ -z "$SLAVE_DATA" ] ; then
      SLAVE_DATA=/home/$SSH_USER/mesos_slave
    fi
    echo SLAVE_DATA=$SLAVE_DATA

    if [ -z "$SLAVE_LOGS" ] ; then
      SLAVE_LOGS=/home/$SSH_USER/mesos_slave_logs
    fi
    echo SLAVE_LOGS=$SLAVE_LOGS

    if [ -z "$MARATHON_DATA" ] ; then
      MARATHON_DATA=/home/$SSH_USER/marathon
    fi
    echo MARATHON_DATA=$MARATHON_DATA

    if [ -z "$MARATHON_LOGS" ] ; then
      MARATHON_LOGS=/home/$SSH_USER/marathon_logs
    fi
    echo MARATHON_LOGS=$MARATHON_LOGS
    echo ZOOKEEPER_ARGS=$ZOOKEEPER_ARGS
    echo MASTER_ARGS=$MASTER_ARGS
    echo SLAVE_ARGS=$SLAVE_ARGS
    echo MARATHON_ARGS=$MARATHON_ARGS

    echo Creating directories on servers. This may take some time. Please wait.
        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX mkdir $ZOOKEEPER_DATA $ZOOKEEPER_LOGS $MASTER_DATA $MASTER_LOGS $MARATHON_DATA $MARATHON_LOGS >/dev/null 2>&1 &
    for i in `seq 0 $LASTSERVER` ; do
        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX mkdir $SLAVE_DATA $SLAVE_LOGS >/dev/null 2>&1 &
    done

    wait

    echo Starting Zookeeper...
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true -p 2181:2181 -p 2888:2888 -p 3888:3888 --name=zookeeper -v $ZOOKEEPER_DATA:/tmp/zookeeper ${ZOOKEEPER_IMAGE_NAME} $ZOOKEEPER_ARGS >/home/$SSH_USER/zookeeper.log"
    do
        echo "Error in remote docker run, retrying..."
    done

    sleep 1
    echo Initializing Mesos master...
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --name=mesos_master --net="host" -p 5050:5050 -v $MASTER_DATA:/data -v $MASTER_LOGS:/logs -e "MESOS_HOSTNAME=${SERVERS_INTERNAL_ARR[0]}" -e "MESOS_IP=${SERVERS_INTERNAL_ARR[0]}" -e "MESOS_ZK=zk://${SERVERS_INTERNAL_ARR[0]}:2181/mesos" -e "MESOS_PORT=5050" -e "MESOS_WORK_DIR=/data" -e "MESOS_LOG_DIR=/logs" -e "MESOS_QUORUM=1" -e "MESOS_REGISTRY=in_memory" -e "MESOS_ROLES=arangodb" --detach=true ${MESOS_IMAGE_NAME} $MASTER_ARGS > /home/$SSH_USER/mesos_master.log"
    do
        echo "Error in remote docker run, retrying..."
    done
    # FIXME: use registry "replicated_log" eventually (or now?)

    sleep 1
    echo Initializing Marathon... 
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --name=marathon -p 8080:8080 --detach=true -v $MARATHON_DATA:/data -v $MARATHON_LOGS:/logs ${MARATHON_IMAGE_NAME} --master zk://${SERVERS_INTERNAL_ARR[0]}:2181/mesos --zk zk://${SERVERS_INTERNAL_ARR[0]}:2181/marathon $MARATHON_ARGS > /home/$SSH_USER/mesos_master.log"
    do
        echo "Error in remote docker run, retrying..."
    done

    start_slave () {
        i=$1
        echo Starting Mesos slave on ${SERVERS_EXTERNAL_ARR[$i]}:

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
            "docker run --detach=true --net=host -v $SLAVE_DATA:/data -v $SLAVE_LOGS:/logs -v /sys:/sys -v /var/run/docker.sock:/var/run/docker.sock --name=mesos_slave_$i --entrypoint="mesos-slave" -e "MESOS_MASTER=zk://${SERVERS_INTERNAL_ARR[0]}:2181/mesos" -e "MESOS_WORK_DIR=/data" -e "MESOS_LOG_DIR=/logs" -e "MESOS_LOGGING_LEVEL=INFO" -e "MESOS_IP=${SERVERS_INTERNAL_ARR[$i]}" -e "MESOS_HOSTNAME=${SERVERS_INTERNAL_ARR[$i]}" -e "MESOS_CONTAINERIZERS=docker,mesos" ${MESOS_IMAGE_NAME} $SLAVE_ARGS >/home/$SSH_USER/slave_$i.log"
        do
            echo "Error in remote docker run, retrying..."
        done
    }

    for i in `seq 0 $LASTSERVER` ; do
        start_slave $i &
    done

    wait

    echo ""
    echo "=============================================================================="
    echo "Done, your cluster is ready."
    echo "=============================================================================="
    echo ""
    echo "Mesos master available at:"
    echo "   http://${SERVERS_EXTERNAL_ARR[0]}:5050"
    echo "Marathon available at:"
    echo "   http://${SERVERS_EXTERNAL_ARR[0]}:8080"
    echo "Zookeeper running at:"
    echo "   http://${SERVERS_EXTERNAL_ARR[0]}:2181"
    echo "Slaves running on machines:"
    for i in `seq 0 $LASTSERVER` ; do
      echo "   ${SERVERS_EXTERNAL_ARR[$i]} (internal IP: ${SERVERS_INTERNAL_ARR[$i]}:5051"
    done
}

