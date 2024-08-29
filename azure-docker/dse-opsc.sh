#!/bin/bash

# Set Azure CLI variables
RESOURCE_GROUP="myDataStaxRG"
LOCATION="eastus"
VM_NAME="myDataStaxVM"
VM_SIZE="Standard_D4s_v3"  # This is a middle-sized VM, adjust as needed
ADMIN_USERNAME="azureuser"

# Create a resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create a VM
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image Ubuntu2204 \
  --admin-username $ADMIN_USERNAME \
  --size $VM_SIZE \
  --generate-ssh-keys

# Get the public IP of the VM
VM_IP=$(az vm show -d -g $RESOURCE_GROUP -n $VM_NAME --query publicIps -o tsv)

# Install Docker on the VM
### Broken
# az vm extension set \
#   --resource-group $RESOURCE_GROUP \
#   --vm-name $VM_NAME \
#   --name customScript \
#   --publisher Microsoft.Azure.Extensions \
#   --settings '{"fileUris": ["https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/docker-simple-on-ubuntu/install-docker.sh"], "commandToExecute": "./install-docker.sh"}'

# Connect to the VM and run Docker commands
ssh $ADMIN_USERNAME@$VM_IP << EOF
  # Add Docker's official GPG key:
  sudo apt-get update
  sudo apt-get install ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update

  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Create a Docker network for DataStax
  sudo docker network create datastax-network

  # Run OpsCenter container
  sudo docker run -d --name opscenter --network datastax-network \
    -e DS_LICENSE=accept \
    -p 8888:8888 \
    datastax/dse-opscenter:6.8.39

  # Run DataStax container
  sudo docker run -d --name datastax --network datastax-network \
    -e DS_LICENSE=accept \
    --link opscenter:opscenter \
    -p 9042:9042 \
    datastax/dse-server:6.8.50

  echo "DataStax and OpsCenter containers are now running."
  echo "You can access OpsCenter at http://$VM_IP:8888"
EOF

echo "Deployment complete. VM IP: $VM_IP"

