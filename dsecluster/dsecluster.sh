#!/bin/bash

function usage() { echo "Usage: $0 [-p root_install_path] [-n number_of_nodes] [-g jvm_memory_size] [-v version] paths/launch/start/stop" 2>&1; exit 1; }

function checkpath() {
    if [ x"$path" == x ]
    then
        echo 'The path parameter not set. You need to use the -p parameter with the paths options';
    exit;
    fi
}

function checknodes() {
    if [ x"$nodes" == x ]
    then
        echo 'The number of nodes parameter not set. You need to use the -n parameter with the paths options';
        exit;
    fi
}

function checkversion(){
    if [ x"$version" == x ]
    then
        echo 'The version parameter not set. You need to use the -v parameter with the launch option.';
        exit;
    fi
}

function checkmem() {
    if [ x"$mem" == x ]
    then
        echo 'The memory parameter not set. You need to use the -g parameter with the launch option.';
        exit;
    fi
}

function path_create() {
    echo 'Creating paths for '$nodes' nodes based at '$path' for DSE '$version'...'
    for i in $(seq 1 $nodes);
    do
        j=$((i - 1))
        echo 'Creating paths for node '$j'...'
        mkdir -p $path$i/dse-$version/node$j/config
        mkdir -p $path$i/dse-$version/node$j/log
        mkdir -p $path$i/dse-$version/node$j/data
    done
    # echo 'Setting authority for the directory to 777.'
    # Nope - chmod 777 -R $path/dse-$version
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

# check for the command run and set parameters or perform actions
case $1 in
    launch)
      checkpath
      checknodes
      checkversion
      checkmem
      
      path_create

      echo 'Creating private network 172.18.0.0'
      docker network create --subnet=172.18.0.0/16 dse-net
      echo 'Creating '$nodes' nodes running DSE '$version' with '$mem' GB JVM memory size each...'
      for i in $(seq 1 $nodes);
      do
	    j=$((i - 1))
	    jvmmem=${mem}G 
	    osmem=$((mem * 2))g
        echo 'Creating node '$j' with ip address 172.18.0.1'$j'...'
        if [ $i == 1 ]; then
            first_seed=172.18.0.1$j
        fi
	    docker run -e DS_LICENSE=accept \
                   --name dse-$version-node$j \
		   -m="$osmem" --memory-swap="$osmem" \
		   --net dse-net --ip="172.18.0.1$j" \
		   -e JVM_EXTRA_OPTS="-Xmx$jvmmem" -e JVM_EXTRA_OPTS="-Xms$jvmmem" \
		   -e SEEDS="$first_seed" \
		   -v $path$i/dse-$version/node$j/data:/var/lib/cassandra:Z \
		   -v $path$i/dse-$version/node$j/log:/var/log/cassandra:Z \
		   -v $path$i/dse-$version/node$j/config:/config:Z \
		   -d datastax/dse-server:$version
      done
      exit
      ;;
    start)
      checknodes
      checkversion

      echo 'Starting nodes for DSE '$version'...'
      for i in $(seq 1 $nodes);
      do
            j=$((i - 1))
            echo 'Starting node '$j'...'
            docker start dse-$version-node$j
	    sleep 30
      done      
      ;;
    stop)
      checknodes
      checkversion

      echo 'Stopping nodes for DSE '$version'...'
      for i in $(seq 1 $nodes);
      do
            j=$((i - 1))
            echo 'Stopping node '$j'...'
            docker stop dse-$version-node$j
	    sleep 10
      done
      ;;
    *)
      usage
      exit
      ;;
esac