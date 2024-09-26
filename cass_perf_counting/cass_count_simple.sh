#!/bin/bash
cass_cont="cassandra_container40"
cass_build="cassandra:4.0"

# Step 1: Create a common Docker network
function create_network {
    echo "Creating common Docker network..."
    docker network create test_network
}

# Prep cass script
cat > init.cql <<EOF
CREATE KEYSPACE test WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
USE test;

CREATE TABLE count_performance (
    key int,
    blob text,
    PRIMARY KEY (key)
);
EOF

function cassandra_build {
    # Step 2: Deploy Cassandra build container
    echo "Deploying $cass_build container..."
    docker run -d --name $cass_cont --network test_network $cass_build

    # Wait for Cassandra to start up
    echo "Waiting for Cassandra to start up..."
    sleep 70

    # Exec the init script
    docker exec -i $cass_cont "ps -ef | grep java" > java_cmd.txt
    docker cp init.cql $cass_cont:init.cql
    docker exec -i $cass_cont cqlsh -f init.cql
    docker exec -i $cass_cont cqlsh -e "describe keyspace test"
}

# read -p "Keyspace ready? Do you want to proceed? (yes/no) " yn

# Step 3: Deploy Python 3.9 container
echo "Deploying Python 3.9 container..."

cat << EOF > Dockerfile
FROM python:3.9
RUN pip install cassandra-driver argparse
COPY objcount.py /app/objcount.py
WORKDIR /app
ENTRYPOINT ["python3", "objcount.py"]
EOF

cleanup () {
    # Clean up
    echo "Cleaning up..."
    docker stop $cass_cont python_container
    docker rm $cass_cont python_container
    docker rm python_container
    docker network rm test_network
    rm Dockerfile
}

function python_build {
    # Build the Python image
    docker build -t python_test_image .

    # Run the Python container
    docker run --name python_container --network test_network python_test_image -i $cass_cont -k test -t count_performance

    read -p "Run of python successful? Do you want to proceed? (yes/no) " yn
    case $yn in 
        yes ) echo ok, we will proceed;
            cleanup;;
        no ) echo exiting...;
            exit;;
        * ) echo invalid response;
            exit 1;;
    esac
}

create_network
cassandra_build
python_build
