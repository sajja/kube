REGISTRY_NAME=""
AKS=""
RG=""
if [ -z $1 ] && [ -z $2 ] && [ -z $3 ]
then
	echo "Usage provision <<aksname>>  <<acrname>> <<new_resouce_group_name>>"
	exit 1
else 
	AKS=$1
	REGISTRY_NAME=$2
	RG=$3
fi

echo "Creating resource group $RG ..."
az group create --name $RG --location southeastasia
echo "Creating ACR: $REGISTRY_NAME"
az acr create --name $REGISTRY_NAME --location southeastasia --resource-group $RG --sku Standard


echo "Create AKS $AKS"
az aks  create --name $AKS --resource-group $RG --location southeastasia


echo "Attach $REGISTRY_NAME to $AKS"
az aks  update --name $AKS --attach-acr $REGISTRY_NAME --resource-group $RG


CONTROLLER_REGISTRY=k8s.gcr.io
CONTROLLER_IMAGE=ingress-nginx/controller
CONTROLLER_TAG=v0.48.1
PATCH_REGISTRY=docker.io
PATCH_IMAGE=jettech/kube-webhook-certgen
PATCH_TAG=v1.5.1
DEFAULTBACKEND_REGISTRY=k8s.gcr.io
DEFAULTBACKEND_IMAGE=defaultbackend-amd64
DEFAULTBACKEND_TAG=1.5

# Please enable this the first time.
# This is commented to save time
az acr import --name $REGISTRY_NAME --source $CONTROLLER_REGISTRY/$CONTROLLER_IMAGE:$CONTROLLER_TAG --image $CONTROLLER_IMAGE:$CONTROLLER_TAG
az acr import --name $REGISTRY_NAME --source $PATCH_REGISTRY/$PATCH_IMAGE:$PATCH_TAG --image $PATCH_IMAGE:$PATCH_TAG
az acr import --name $REGISTRY_NAME --source $DEFAULTBACKEND_REGISTRY/$DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG --image $DEFAULTBACKEND_IMAGE:$DEFAULTBACKEND_TAG


echo "Configuring kubectl..."
az aks get-credentials --resource-group $RG --name $AKS


# Create a namespace for your ingress resources
echo "Creating namespace .....................>"
kubectl create namespace ib

# Add the ingress-nginx repository
echo "Adding helm repo nginx.....................>"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Set variable for ACR location to use for pulling images
ACR_URL="$REGISTRY_NAME.azurecr.io"


echo "Creating ingress controller ......................."
# Use Helm to deploy an NGINX ingress controller
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace "ib" \
    --set controller.replicaCount=1 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.image.registry=$ACR_URL \
    --set controller.image.image=$CONTROLLER_IMAGE \
    --set controller.image.tag=$CONTROLLER_TAG \
     --set controller.image.digest="" \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.image.registry=$ACR_URL \
    --set controller.admissionWebhooks.patch.image.image=$PATCH_IMAGE \
    --set controller.admissionWebhooks.patch.image.tag=$PATCH_TAG \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.image.registry=$ACR_URL \
    --set defaultBackend.image.image=$DEFAULTBACKEND_IMAGE \
    --set defaultBackend.image.tag=$DEFAULTBACKEND_TAG


echo "Creating ingress..."
kubectl apply -f ingress.yaml --namespace ib

echo "Deploying the services ..."
kubectl apply -f basic.yaml --namespace ib
