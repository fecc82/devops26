# Source: https://gist.github.com/cf939640f2af583c3a12d04affa67923

####################
# Create a cluster #
####################

# Install gcloud CLI (https://cloud.google.com/sdk/docs/quickstarts) and make sure that you have GCP admin permissions

# Open https://console.cloud.google.com/cloud-resource-manager to create a new GCP project if you do not have one available already. Make sure to enable billing for that project.

export PROJECT=[...] # Replace `[...]` with the name of the GCP project (e.g. jx).

echo "nexus:
  enabled: false
" | tee myvalues.yaml

jx create cluster gke \
    --cluster-name jx-rocks \
    --project-id $PROJECT \
    --region us-east1 \
    --machine-type n1-standard-2 \
    --min-num-nodes 1 \
    --max-num-nodes 2 \
    --default-admin-password=admin \
    --default-environment-prefix jx-rocks \
    --git-provider-kind github \
    --namespace jx \
    --prow \
    --tekton

# If asked for input, use the default answers unless you're sure you want a non-standard setup.

############################
# Install Gloo And Knative #
############################

glooctl install knative \
    --install-knative-version=0.9.0

jx edit deploy \
    --team \
    --kind knative \
    --batch-mode

KNATIVE_IP=$(kubectl \
    --namespace gloo-system \
    get service knative-external-proxy \
    --output jsonpath="{.status.loadBalancer.ingress[0].ip}")

echo $KNATIVE_IP

# Confirm that the IP exists (that the LB was created)

echo "apiVersion: v1
kind: ConfigMap
metadata:
  name: config-domain
  namespace: knative-serving
data:
  $KNATIVE_IP.nip.io: \"\"" \
    | kubectl apply --filename -

#######################
# Destroy the cluster #
#######################

gcloud container clusters \
    delete jx-rocks \
    --region us-east1 \
    --quiet

# Remove unused disks to avoid reaching the quota (and save a bit of money)
gcloud compute disks delete \
    --zone us-east1-b \
    $(gcloud compute disks list \
    --filter="zone:us-east1-b AND -users:*" \
    --format="value(id)") --quiet
gcloud compute disks delete \
    --zone us-east1-c \
    $(gcloud compute disks list \
    --filter="zone:us-east1-c AND -users:*" \
    --format="value(id)") --quiet
gcloud compute disks delete \
    --zone us-east1-d \
    $(gcloud compute disks list \
    --filter="zone:us-east1-d AND -users:*" \
    --format="value(id)") --quiet

# Remove container images from GCR
IMAGE=go-demo-6
for TAG in $(gcloud container images \
  list-tags gcr.io/$PROJECT/$IMAGE \
  --format='get(tags)')
do
  gcloud container images \
    delete gcr.io/$PROJECT/$IMAGE:$TAG \
    --quiet
done
