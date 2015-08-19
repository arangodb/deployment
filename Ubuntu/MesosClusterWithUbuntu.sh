#
# This script is provided as-is, no warrenty is provided or implied.
# The author is NOT responsible for any damages or data loss that may occur through the use of this script.
#
# This function starts an ArangoDB cluster by just using docker
#
# Prerequisites:
# The following environment variables are used:
#   OUTPUT           : a path to a directory with the cluster information
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
#   SSH_USER         : user name on remote machine [default "ubuntu"]
#   SSH_SUFFIX       : suffix for ssh command [default ""].

# There will be one Zookeeper instance running on the first machine.
# There will be one Mesos master instance running on the first machine.
# There will be one Mesos slave on each machine.
# There will be one instance of Marathon on the first machine.

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[i]} ${SSH_SUFFIX} sudo docker run ...

startMesosClusterOnUbuntu() {
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
      SSH_USER=ubuntu
    fi
    echo SSH_USER=$SSH_USER

    cat <<'EOF' >$OUTPUT/prepareUbuntuMaster.sh
#!/bin/bash
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)
echo "deb http://repos.mesosphere.io/${DISTRO} ${CODENAME} main" | tee /etc/apt/sources.list.d/mesosphere.list
apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
apt-get -y update
apt-get -y install curl python-setuptools python-pip python-dev python-protobuf
apt-get -y install zookeeperd zookeeper mesos docker.io lxc marathon
EOF
    cat <<EOF >>$OUTPUT/prepareUbuntuMaster.sh
echo zk://${SERVERS_INTERNAL_ARR[0]}:2181/mesos >/etc/mesos/zk
echo "HOSTNAME=${SERVERS_INTERNAL_ARR[0]}" >>/etc/default/mesos-master
echo "IP=${SERVERS_INTERNAL_ARR[0]}" >>/etc/default/mesos-master
service mesos-master restart
echo "IP=${SERVERS_INTERNAL_ARR[0]}" >>/etc/default/mesos-slave
echo "export MESOS_CONTAINERIZERS=docker,mesos" >>/etc/default/mesos-slave
service mesos-slave restart
service marathon restart
adduser ubuntu docker
EOF
    chmod 755 $OUTPUT/prepareUbuntuMaster.sh

    for i in `seq 1 $LASTSERVER` ; do
        cat <<'EOF' >$OUTPUT/prepareUbuntu_$i.sh
#!/bin/bash
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)
echo "deb http://repos.mesosphere.io/${DISTRO} ${CODENAME} main" | tee /etc/apt/sources.list.d/mesosphere.list
apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
apt-get -y update
apt-get -y install curl python-setuptools python-pip python-dev python-protobuf
apt-get -y install mesos docker.io lxc
service mesos-master stop
service zookeeper stop
rm /etc/init/mesos-master.conf
rm /etc/init/zookeeper.conf
adduser ubuntu docker
EOF
        cat <<EOF >>$OUTPUT/prepareUbuntu_$i.sh
echo zk://${SERVERS_INTERNAL_ARR[0]}:2181/mesos >/etc/mesos/zk
echo "IP=${SERVERS_INTERNAL_ARR[$i]}" >>/etc/default/mesos-slave
echo "export MESOS_CONTAINERIZERS=docker,mesos" >>/etc/default/mesos-slave
service mesos-slave restart
EOF
        chmod 755 $OUTPUT/prepareUbuntu_$i.sh
    done

    echo Preparing master...
    scp -o"StrictHostKeyChecking no" $OUTPUT/prepareUbuntuMaster.sh ubuntu@${SERVERS_EXTERNAL_ARR[0]}:
    ssh -o"StrictHostKeyChecking no" ubuntu@${SERVERS_EXTERNAL_ARR[0]} "sudo ./prepareUbuntuMaster.sh"

    echo "Preparing slaves (parallel)..."
    for i in `seq 1 $LASTSERVER` ; do
        ip=${SERVERS_EXTERNAL_ARR[$i]}
        echo Preparing slave $ip...
        scp -o"StrictHostKeyChecking no" $OUTPUT/prepareUbuntu_$i.sh ubuntu@$ip:
        ssh -o"StrictHostKeyChecking no" ubuntu@$ip "sudo ./prepareUbuntu_$i.sh" &
    done

    wait

    echo ""
    echo "=============================================================================="
    echo "Done, your cluster is ready."
    echo "=============================================================================="
    echo ""
    echo "Mesos master available at:"
    echo "   http://${SERVERS_EXTERNAL_ARR[0]}:5050 (internal IP: ${SERVERS_INTERNAL_ARR[0]})"
    echo "Marathon available at:"
    echo "   http://${SERVERS_EXTERNAL_ARR[0]}:8080"
    echo "Zookeeper running at:"
    echo "   http://${SERVERS_EXTERNAL_ARR[0]}:2181"
    echo "Slaves running on machines:"
    for i in `seq 0 $LASTSERVER` ; do
        echo "   ubuntu@${SERVERS_EXTERNAL_ARR[$i]} (internal IP: ${SERVERS_INTERNAL_ARR[$i]}:5051)"
    done
}

