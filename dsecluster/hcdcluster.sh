#!/bin/bash
# Blame Peter G for any issues

usage() { 
    echo "Usage: $0 [-p root_install_path] [-n number_of_nodes] [-g jvm_memory_size] [-v version] prepare/launch/start/stop/remove/destroy"
    echo "For example, run the command:"
    echo -e "\t$0 -p /docker -n 3 -v 1.0.0 prepare"
    echo "to create the paths required and extract configuration files. These paths will contain the persistent data for the nodes in the local file system."
    echo "Note that the /docker path needs to already exist and the user running this command need to have sufficient access to it."
    echo "For example run the following to create the directory:"
    echo -e "\tsudo mkdir /docker"
    echo "Then run the following to give access to the docker group:"
    echo -e "\tsudo chown :docker /docker" 
    echo "Then run:"
    echo -e "\t$0 -p /docker -n 3 -v 1.0.0 -g 2 launch"
    echo "to create the docker containers."
    echo "The remove command will delete the containers but leave the persistent data."
    echo "The destory command will give you the command to permanently delete the persistent data."
    echo "The version names can be found in the dcoker hub at: https://hub.docker.com/r/datastax/hcd/tags"
    exit 1; 
}

while getopts "p:n:g:v:h:" o; do
    case "${o}" in
        p)
            path=${OPTARG}
            ;;
        n)
	        nodes=${OPTARG}
            ;;
     	  g)
            mem=${OPTARG}
            ;;
        v)
            version=${OPTARG}
            ;;
        h)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

checkpath() {
    if [ x"$path" == x ]
    then
        echo 'The path parameter not set. You need to use the -p parameter with the '$cmdopt' option.';
        exit 1;
    fi
}

checknodes() {
    if [ x"$nodes" == x ]
    then
        echo 'The number of nodes parameter not set. You need to use the -n parameter with the '$cmdopt' option.';
        exit 1;
    fi
}

checkversion(){
    if [ x"$version" == x ]
    then
        echo 'The version parameter not set. You need to use the -v parameter with the '$cmdopt' option.';
        exit 1;
    fi
}

checkmem() {
    if [ x"$mem" == x ]
    then
        echo 'The memory parameter not set. You need to use the -g parameter with the '$cmdopt' option.';
        exit 1;
    fi
}

create_paths () {
      echo 'Creating paths for '$nodes' nodes based at '$path' for HCD '$version'...'
      for i in $(seq 1 $nodes);
      do
        j=$((i - 1))
	    echo 'Creating paths for node '$j'...'
	    sudo mkdir -p $path/hcd-$version/node$j/config
	    sudo mkdir -p $path/hcd-$version/node$j/log
	    sudo mkdir -p $path/hcd-$version/node$j/data
      done
      echo 'Setting authority for the directory to 777.'
      sudo chmod 777 -R $path/hcd-$version
      echo 'Extracting cassandra.yaml files..'
      for s in $(seq 1 $nodes);
      do
        t=$((s - 1))
        echo 'For node'$t
        docker cp tmphcd-$version:/opt/hcd/resources/cassandra/conf/cassandra.yaml $path/hcd-$version/node$t/config
        if [ "$s" -ne "1" ]
        then
            echo ' Setting allocate_tokens_for_local_replication_factor to 3'
            echo 'allocate_tokens_for_local_replication_factor: 3' >> $path/hcd-$version/node$t/config/cassandra.yaml
        fi
      done
}

create_stubimage() {
    echo 'Creating temporary image to extract configuration files from...'
    docker create --name tmphcd-$version docker.io/datastax/hcd:$version
}

delete_stubimage() {
    echo 'Removing temporary image...'
    docker rm tmphcd-$version
}


destroy_paths () {
      echo 'Creating command to remove paths for configuration at '$path' for HCD '$version'...'
      echo 'Run the command:'
      echo -e '\tsudo rm -rf '$path'/hcd-'$version
      echo 'The script will not do this for you in case you have put in the wrong path.'
}

create_network () {
      echo 'Creating private network 172.22.0.0'
      docker network create --subnet=172.22.0.0/16 hcd-net
}

remove_network () {
      echo 'Removing private network 172.22.0.0'
      docker network rm hcd-net
}

launch_nodes () {
      echo 'Creating '$nodes' nodes running HCD '$version' with '$mem' GB JVM memory size each...'
      for i in $(seq 1 $nodes);
      do
	    j=$((i - 1))
	    jvmmem=${mem}G 
	    osmem=$((mem * 2))g
            echo 'Creating node '$j' with ip address 172.22.0.1'$j'...'
	    docker run -e DS_LICENSE=accept \
           --name hcd-$version-node$j \
		   -m="$osmem" --memory-swap="$osmem" \
		   --net hcd-net --ip="172.22.0.1$j" \
		   -e JVM_EXTRA_OPTS="-Xmx$jvmmem -Xms$jvmmem" \
		   -e SEEDS="172.22.0.10" \
       -e NUM_TOKENS="8" \
		   -v $path/hcd-$version/node$j/data:/var/lib/cassandra \
		   -v $path/hcd-$version/node$j/log:/var/log/cassandra \
		   -v $path/hcd-$version/node$j/config:/config \
		   -d docker.io/datastax/hcd:$version
        echo "Waiting 60 seconds to allow the nodes to start..."
        sleep 60
      done
}

remove_nodes () {
      echo 'Removing the '$nodes' nodes for HCD '$version'...'
      for i in $(seq 1 $nodes);
      do
	    j=$((i - 1))
        echo 'Deleting node hcd-'$version'-node'$j'...'
	    docker rm hcd-$version-node$j
      done
}

start_nodes () {
      echo 'Starting nodes for hcd '$version'...'
      for i in $(seq 1 $nodes);
      do
            j=$((i - 1))
            echo 'Starting node '$j'...'
            docker start hcd-$version-node$j
	    sleep 30
      done      
}

stop_nodes () {
      echo 'Stopping nodes for HCD '$version'...'
      for i in $(seq 1 $nodes);
      do
            j=$((i - 1))
            echo 'Stopping node '$j'...'
            docker stop hcd-$version-node$j
	    sleep 10
      done
}

# check for the command run and set parameters or perform actions
cmdopt=$1
case $cmdopt in
    prepare)
      checkpath
      checknodes
      checkversion
      create_stubimage
      create_paths
      delete_stubimage
      ;;
    launch)
      checkpath
      checknodes
      checkversion
      checkmem
      create_network
      launch_nodes
      ;;
    start)
      checknodes
      checkversion
      start_nodes
      ;;
    stop)
      checknodes
      checkversion
      stop_nodes
      ;;
    destroy)
      checkpath
      checkversion
      destroy_paths
      ;;
    remove)
      checknodes
      checkversion
      remove_nodes
      ;;
    *)
      usage
      ;;
esac
