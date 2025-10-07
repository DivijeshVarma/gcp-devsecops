#!/bin/bash

#Run the following ONE-TIME-SCRIPT which creates and provisions the necessary GCP cloud services that will be required to create the DevSecOps CICD pipeline for a sample docker application. Here's all the service deployments that will occur once the script finishes:


#Enable the following GCP APIs
#Cloud Build, Binary Authorization, On-Demand Scanning, Resource Manager API, Artifact Registry API, Artifact Registry Vulnerability Scanning, Cloud Deploy API, KMS API and Cloud Functions.
gcloud services enable cloudbuild.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable ondemandscanning.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable containerscanning.googleapis.com
gcloud services enable clouddeploy.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable secretmanager.googleapis.com


#GCP Project Variables
LOCATION=asia-south1
PROJECT_ID=fit-sanctum
BUCKET_NAME="bucket-$(date +%s)"
PROJECT_NUMBER=956631446301
CLOUD_BUILD_SA_EMAIL="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

#Create the following custom IAM role
gcloud iam roles create cicdblogrole --project=${PROJECT_ID} \
    --title="cicdblogrole" \
    --description="Custom Role for GCP CICD Blog" \
    --permissions="artifactregistry.repositories.create,container.clusters.get,clouddeploy.deliveryPipelines.get,clouddeploy.releases.get,containeranalysis.notes.attachOccurrence,containeranalysis.notes.create,containeranalysis.notes.listOccurrences,containeranalysis.notes.setIamPolicy,iam.serviceAccounts.actAs,ondemandscanning.operations.get,ondemandscanning.scans.analyzePackages,ondemandscanning.scans.listVulnerabilities,serviceusage.services.enable,storage.objects.get" \
    --stage=Beta

#Add the newly created custom role, and "Cloud Deploy Admin" to the Cloud Build Service Account
gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:${CLOUD_BUILD_SA_EMAIL}" --role="projects/${PROJECT_ID}/roles/cicdblogrole"

gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:${CLOUD_BUILD_SA_EMAIL}" --role='roles/clouddeploy.admin'

#Add the following: "Artifact Registry Reader", "Cloud Deploy Runner" and "Kubernetes Engine Admin" IAM Role to the Compute Engine Service Account
gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:${COMPUTE_SA}" --role='roles/artifactregistry.reader'

gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:${COMPUTE_SA}" --role='roles/clouddeploy.jobRunner'

gcloud projects add-iam-policy-binding ${PROJECT_ID} --member="serviceAccount:${COMPUTE_SA}" --role='roles/container.admin'

#Create Artifact Registry Repository where images will be stored
gcloud artifacts repositories create test-repo \
    --repository-format=Docker \
    --location=$LOCATION \
    --description="Artifact Registry for GCP DevSecOps CICD Blog" \
    --async

# Create Bucket for DAST scan

gcloud storage buckets create "gs://$BUCKET_NAME" --location=$LOCATION

# make bucket public

gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME 

#This plugin is required for your kubectl command-line tool to authenticate with the GKE clusters.
gcloud components install gke-gcloud-auth-plugin

#Create three GKE clusters for test, staging and production.

#GKE Cluster for Test environment, uncomment --subnetwork if you want to use a non-default VPC
gcloud container clusters create test \
    --project=$PROJECT_ID \
    --zone=asia-south1-a \
    --enable-ip-alias \
    --machine-type=e2-small \
    --disk-size=20 \
    --num-nodes=1 \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=3 \
    --autoscaling-profile=optimize-utilization \
    --enable-vertical-pod-autoscaling \
    --release-channel=regular \
    --enable-autorepair \
    --enable-autoupgrade \
    --labels=app=webserver

TEST_IP=$(gcloud compute addresses create test-ip --region=$LOCATION --project=$PROJECT_ID --format='value(address)')

STAGING_IP=$(gcloud compute addresses create staging-ip --region=$LOCATION --project=$PROJECT_ID --format='value(address)')

PROD_IP=$(gcloud compute addresses create prod-ip --region=$LOCATION --project=$PROJECT_ID --format='value(address)')

#GKE Cluster for Staging environment
gcloud container clusters create staging \
    --project=$PROJECT_ID \
    --zone=asia-south1-a \
    --enable-ip-alias \
    --machine-type=e2-small \
    --disk-size=20 \
    --num-nodes=1 \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=3 \
    --autoscaling-profile=optimize-utilization \
    --enable-vertical-pod-autoscaling \
    --release-channel=regular \
    --enable-autorepair \
    --enable-autoupgrade \
    --labels=app=webserver

#GKE Cluster for Production environment
gcloud container clusters create prod \
    --project=$PROJECT_ID \
    --zone=asia-south1-a \
    --enable-ip-alias \
    --machine-type=e2-small \
    --disk-size=20 \
    --num-nodes=1 \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=3 \
    --autoscaling-profile=optimize-utilization \
    --enable-vertical-pod-autoscaling \
    --release-channel=regular \
    --enable-autorepair \
    --enable-autoupgrade \
    --labels=app=webserver

#Create cloud deploy pipeline
gcloud deploy apply --file clouddeploy.yaml --region=$LOCATION --project=$PROJECT_ID

# Install NGINX Ingress Controller on the 'test' cluster
gcloud container clusters get-credentials test --region $LOCATION --project $PROJECT_ID

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.loadBalancerIP=$TEST_IP

# Install NGINX Ingress Controller on the 'staging' cluster
gcloud container clusters get-credentials staging --region $LOCATION --project $PROJECT_ID

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.loadBalancerIP=$STAGING_IP

# Install NGINX Ingress Controller on the 'prod' cluster
gcloud container clusters get-credentials prod --region $LOCATION --project $PROJECT_ID

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.service.loadBalancerIP=$PROD_IP

echo "====================="

# Display the static IP address on the screen
echo "The Test IP address created is: $TEST_IP"

echo "The Staging IP address created is: $STAGING_IP"

echo "The Prod IP address created is: $PROD_IP"

# Display Bucket Name
echo "Bucket Name: $BUCKET_NAME"

echo "====================="
