#!/bin/bash

set -e

# Constants
CASSANDRA_IMAGE="cassandra:4.1.4"
CONTAINER_NAME="cassandra-4.1.4"
VOLUME_NAME="cassandra41-data"
NETWORK_NAME="cassandra-net"
CQL_SCRIPT="/tmp/init.cql"
CQLU_SCRIPT="/tmp/update.cql"
CQLD_SCRIPT="/tmp/delete.cql"
CONFIG_DIR="$(pwd)/cassandra-config"
LOG_FILE="cassandra41_logs.txt"

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
CREATE KEYSPACE test WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
USE test;

CREATE TABLE daily_tiered_import_size (
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
USE test;
UPDATE daily_tiered_import_size set imported_tier_data_size= imported_tier_data_size+76167372947893 where day = 20240725 and tier_level = 1 and hour = -1 and pgc_key = -1;
SELECT * from daily_tiered_import_size where day = 20240725 and tier_level = 1;
EOF

cat > delete.cql <<EOF
USE test;
DELETE FROM daily_tiered_import_size where day = 20240725 and tier_level = 1 and hour = -1 and pgc_key = -1;
SELECT * from daily_tiered_import_size where day = 20240725 and tier_level = 1;
EOF

# Function to extract cassandra.yaml from a container
extract_cassandra_yaml() {
    local image=$1
    local output_dir=$2
    local container_name="temp_container"

    docker create --name $container_name $image
    docker cp $container_name:/etc/cassandra/cassandra.yaml $output_dir
    docker rm $container_name
}

# Extract cassandra.yaml from Cassandra image
extract_cassandra_yaml $CASSANDRA_IMAGE $CONFIG_DIR

sed -i 's/counter_cache_size_in_mb:/counter_cache_size_in_mb: 0/' $CONFIG_DIR/cassandra.yaml

# Start Cassandra container
docker run --name $CONTAINER_NAME -d \
    --network $NETWORK_NAME \
    -v $VOLUME_NAME:/var/lib/cassandra \
    -v $CONFIG_DIR/cassandra.yaml:/etc/cassandra/cassandra.yaml \
    -p 9042:9042 \
    $CASSANDRA_IMAGE

# Wait for Cassandra to start
echo "Waiting for Cassandra to start..."
sleep 70

# Execute the CQL script
docker cp init.cql $CONTAINER_NAME:$CQL_SCRIPT
docker cp update.cql $CONTAINER_NAME:$CQLU_SCRIPT
docker cp delete.cql $CONTAINER_NAME:$CQLD_SCRIPT
docker exec -i $CONTAINER_NAME cqlsh -f $CQL_SCRIPT

for i in {0..10}; do
    docker exec -i $CONTAINER_NAME cqlsh -f $CQLU_SCRIPT
    sleep 5
    docker exec -i $CONTAINER_NAME cqlsh -f $CQLD_SCRIPT
    sleep 5
done

sleep 15
docker logs $CONTAINER_NAME > $LOG_FILE

read -p "Press Enter to continue" </dev/tty

# Stop Cassandra 4.0 container
docker stop $CONTAINER_NAME
docker rm $CONTAINER_NAME
