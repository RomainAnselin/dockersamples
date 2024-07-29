#!/bin/bash

set -e

# Constants
CASSANDRA2_IMAGE="cassandra:2.2"
CASSANDRA3_IMAGE="cassandra:3.11"
CASSANDRA4_IMAGE="cassandra:4.0"
CONTAINER2_NAME="cassandra-2.2"
CONTAINER3_NAME="cassandra-3.11"
CONTAINER4_NAME="cassandra-4.0"
VOLUME_NAME="cassandra-data"
NETWORK_NAME="cassandra-net"
CQL_SCRIPT="/tmp/init.cql"
CONFIG_DIR="$(pwd)/cassandra-config"
LOG_FILE="cassandra4_logs.txt"

# Clean up any existing containers
docker rm -f $CONTAINER2_NAME $CONTAINER3_NAME $CONTAINER4_NAME || true
docker volume rm $VOLUME_NAME || true
rm -r $CONFIG_DIR || true

# Create a network for communication between containers
docker network create $NETWORK_NAME || true

# Create a persistent volume
docker volume create $VOLUME_NAME

# Create configuration directory
mkdir -p $CONFIG_DIR

# Write CQL script to initialize Cassandra
cat > init.cql <<EOF
CREATE KEYSPACE testkeyspace WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
USE testkeyspace;

CREATE TABLE repro02 (id text, c2 text, version text, primary key(id)) WITH COMPACT STORAGE;
INSERT INTO repro02 (id,c2,version) values ('a','b','v01');
CREATE INDEX idx_repro02 ON repro02 (c2);
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

# Extract cassandra.yaml from Cassandra 2.2 image
extract_cassandra_yaml $CASSANDRA2_IMAGE $CONFIG_DIR

# Start Cassandra 2.2 container
docker run --name $CONTAINER2_NAME -d \
    --network $NETWORK_NAME \
    -v $VOLUME_NAME:/var/lib/cassandra \
    -v $CONFIG_DIR/cassandra.yaml:/etc/cassandra/cassandra.yaml \
    -p 9042:9042 \
    $CASSANDRA2_IMAGE

# Wait for Cassandra 2.2 to start
echo "Waiting for Cassandra 2.2 to start..."
sleep 30

# Execute the CQL script
docker cp init.cql $CONTAINER2_NAME:$CQL_SCRIPT
docker exec -i $CONTAINER2_NAME cqlsh -f $CQL_SCRIPT

#docker exec -i $CONTAINER2_NAME cqlsh -e "SELECT * FROM testkeyspace.testtable;"
docker exec -i $CONTAINER2_NAME cqlsh -e "SELECT * FROM testkeyspace.repro02 where c2 = 'b';"

# Flush the data to disk
docker exec -i $CONTAINER2_NAME nodetool flush
docker exec -i $CONTAINER2_NAME nodetool drain
sleep 15
docker exec -i $CONTAINER2_NAME ls -ltraAR /var/lib/cassandra/data/testkeyspace/
docker logs $CONTAINER2_NAME > cassandra22_logs.txt

# Stop Cassandra 2.2 container
docker stop $CONTAINER2_NAME
docker rm $CONTAINER2_NAME

# Start Cassandra 3.11 container
docker run --name $CONTAINER3_NAME -d \
    --network $NETWORK_NAME \
    -v $VOLUME_NAME:/var/lib/cassandra \
    -v $CONFIG_DIR/cassandra.yaml:/etc/cassandra/cassandra.yaml \
    -p 9042:9042 \
    $CASSANDRA3_IMAGE

# Wait for Cassandra 3.11 to start
echo "Waiting for Cassandra 3.11 to start..."
sleep 30

# Upgrade SSTables in Cassandra 3.11
docker exec -i $CONTAINER3_NAME nodetool upgradesstables

# Verify the data in Cassandra 3.11
#docker exec -i $CONTAINER3_NAME cqlsh -e "SELECT * FROM testkeyspace.testtable;"
docker exec -i $CONTAINER3_NAME cqlsh -e "SELECT * FROM testkeyspace.repro02 where c2 = 'b';"
docker exec -i $CONTAINER3_NAME ls -ltraAR /var/lib/cassandra/data/testkeyspace/
#docker exec -i $CONTAINER3_NAME ls -ltr /var/lib/cassandra/data/testkeyspace/repro02-*/.idx_repro02/

docker logs $CONTAINER3_NAME > cassandra311_logs.txt
# Stop Cassandra 3.11 container
docker stop $CONTAINER3_NAME
docker rm $CONTAINER3_NAME

# Extract cassandra.yaml from Cassandra 4.0 image
extract_cassandra_yaml $CASSANDRA4_IMAGE $CONFIG_DIR

# Modify the num_tokens value in cassandra.yaml for Cassandra 4.0
sed -i 's/num_tokens: 16/num_tokens: 256/' $CONFIG_DIR/cassandra.yaml

# Start Cassandra 4.0 container
docker run --name $CONTAINER4_NAME -d \
    --network $NETWORK_NAME \
    -v $VOLUME_NAME:/var/lib/cassandra \
    -v $CONFIG_DIR/cassandra.yaml:/etc/cassandra/cassandra.yaml \
    -p 9042:9042 \
    $CASSANDRA4_IMAGE

# Wait for Cassandra 4.0 to start
echo "Waiting for Cassandra 4.0 to start..."
sleep 30

#docker exec -i $CONTAINER4_NAME cqlsh -e "SELECT * FROM testkeyspace.testtable;"
docker exec -i $CONTAINER4_NAME cqlsh -e "SELECT * FROM testkeyspace.repro02 where c2 = 'b';"
docker exec -i $CONTAINER4_NAME ls -ltraAR /var/lib/cassandra/data/testkeyspace/
#docker exec -i $CONTAINER4_NAME ls -ltr /var/lib/cassandra/data/testkeyspace/repro02-*/.idx_repro02/

# Extract logs from Cassandra 4.0
docker logs $CONTAINER4_NAME > $LOG_FILE

# Clean up
rm init.cql

echo "Cassandra 4.0 environment setup complete. Logs are available in $LOG_FILE."
