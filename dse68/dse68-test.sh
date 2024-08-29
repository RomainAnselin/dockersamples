#!/bin/bash
set -e

# Constants
ver=6.8.50
DSE_IMAGE="datastax/dse-server:$ver"
CONTAINER_NAME="dse-$ver"
VOLUME_NAME="dse$ver-data"
NETWORK_NAME="cassandra-net"
CQL_SCRIPT="/tmp/init.cql"
CQLU_SCRIPT="/tmp/update.cql"
CQLD_SCRIPT="/tmp/delete.cql"
CONFIG_DIR="$(pwd)/cassandra-config"
LOG_FILE="cassandra41_logs.txt"

keyspace="test"
table="my_table"

# Clean up any existing containers
docker rm -f $CONTAINER_NAME || true
docker volume rm $VOLUME_NAME || true
rm -rf $CONFIG_DIR || true

# Create a network for communication between containers
docker network create $NETWORK_NAME || true

# Create a persistent volume
docker volume create $VOLUME_NAME

# Create configuration directory
mkdir -p $CONFIG_DIR

# Write CQL script to initialize Cassandra
cat > init.cql <<EOF
CREATE KEYSPACE $keyspace WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
USE $keyspace;

CREATE TABLE $table (
    day int,
    tier_level int,
    hour int,
    pgc_key int,
    imported_lg_key_count counter,
    imported_tier_data_size counter,
    PRIMARY KEY ((day, tier_level), hour, pgc_key)
) WITH gc_grace_seconds = 1;
EOF

cat > update.cql <<EOF
USE $keyspace;
UPDATE $table set imported_tier_data_size= imported_tier_data_size+76167372947893 where day = 20240725 and tier_level = 1 and hour = -1 and pgc_key = -1;
SELECT * from $table where day = 20240725 and tier_level = 1;
EOF

# Function to extract cassandra.yaml from a container
extract_cassandra_yaml() {
    local image=$1
    local output_dir=$2
    local container_name="temp_container"

    docker create --name $container_name $image
    docker cp $container_name:/opt/dse/resources/cassandra/conf/cassandra.yaml $output_dir
    docker rm $container_name
}

# Extract cassandra.yaml from Cassandra image
extract_cassandra_yaml $DSE_IMAGE $CONFIG_DIR

# Start Cassandra container
docker run --name $CONTAINER_NAME -d \
    --network $NETWORK_NAME \
    -e DS_LICENSE=accept \
    -v $VOLUME_NAME:/var/lib/cassandra \
    -v $CONFIG_DIR/cassandra.yaml:/etc/dse/cassandra/cassandra.yaml \
    -p 9042:9042 \
    $DSE_IMAGE -g -k -s

docker cp init.cql $CONTAINER_NAME:$CQL_SCRIPT
sleep 60

docker exec -i $CONTAINER_NAME cqlsh -f $CQL_SCRIPT

# To copy the sstable, you need the UUID of the table created
read -p "Provide UUID: " uuid


docker cp /path/to/sstables $CONTAINER_NAME:/var/lib/cassandra/data/$keyspace/tenant_b_c360-$uuid/
docker exec -i $CONTAINER_NAME nodetool import $keyspace $table
docker exec -i $CONTAINER_NAME nodetool scrub

read -p "Press Enter to continue" </dev/tty
docker logs $CONTAINER_NAME > $LOG_FILE


# Stop Cassandra 4.0 container
docker stop $CONTAINER_NAME
docker rm $CONTAINER_NAME

