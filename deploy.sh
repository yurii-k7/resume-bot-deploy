#!/bin/bash

# Resume Bot Full Stack Deployment Script
set -e

# Change to the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "🚀 Starting Resume Bot Full Stack Deployment..."

# Usage information
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0            # Build, push to ECR, and deploy"
    echo ""
    echo "Environment variables:"
    echo "  CDK_DEFAULT_REGION   # AWS region (default: ca-central-1)"
    exit 0
fi

# Always build and push to ECR
echo "📦 Building and pushing to ECR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    print_error "Please run this script from the resume-bot-deploy directory"
    exit 1
fi

# Load environment variables from .env file
print_status "Loading environment variables from .env file..."
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
    print_status "Environment variables loaded"
else
    print_warning ".env file not found"
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    print_error "AWS CLI is not configured or credentials are invalid"
    print_warning "Please run 'aws configure' to set up your credentials"
    exit 1
fi

print_status "AWS credentials verified"

# Install CDK dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    print_status "Installing CDK dependencies..."
    npm install
fi

# Build CDK TypeScript
print_status "Building CDK TypeScript..."
npm run build

# Get AWS account ID and default region
CDK_ACCOUNT=${CDK_DEFAULT_ACCOUNT:-$(aws sts get-caller-identity --query Account --output text)}
CDK_REGION=${CDK_DEFAULT_REGION:-$(aws configure get region || echo "ca-central-1")}

# Export environment variables for CDK
export CDK_DEFAULT_ACCOUNT=$CDK_ACCOUNT
export CDK_DEFAULT_REGION=$CDK_REGION

print_status "Using AWS Account: $CDK_ACCOUNT"
print_status "Using Default Region: $CDK_REGION"

# Build and push Docker image to ECR using backend script
print_status "Building and pushing Docker image to ECR..."

# Run the backend build and push script
../resume-bot-backend/scripts/build-and-push.sh

# NOW get the latest ECR image URI (after potentially building new one)
print_status "Getting latest timestamped ECR image URI (excluding 'latest' tag)..."
# First get all tags from the most recent image, then filter out 'latest' in bash
ALL_TAGS=$(aws ecr describe-images \
    --repository-name resume-bot/backend-lambda \
    --region $CDK_REGION \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags' \
    --output text)

# Filter out 'latest' tag and get the first remaining tag
LATEST_TAG=""
for tag in $ALL_TAGS; do
    if [[ "$tag" != "latest" ]]; then
        LATEST_TAG="$tag"
        break
    fi
done

if [ "$LATEST_TAG" != "None" ] && [ ! -z "$LATEST_TAG" ]; then
    ECR_IMAGE_URI="${CDK_ACCOUNT}.dkr.ecr.${CDK_REGION}.amazonaws.com/resume-bot/backend-lambda:${LATEST_TAG}"
    export RESUME_BOT_ECR_IMAGE_URI=$ECR_IMAGE_URI
    print_status "Using ECR image: $ECR_IMAGE_URI"
else
    print_error "No images found in ECR repository. Please run the build script first."
    print_warning "Run: cd ../resume-bot-backend && ./scripts/build-and-push.sh"
    exit 1
fi

# Note: CDK bootstrap is NOT needed for ECR-based deployment
# Bootstrap is only required for CDK assets (which we're not using)
print_status "Skipping CDK bootstrap (not needed for ECR deployment)"

# Deploy the certificate stack first (must be in us-east-1 for CloudFront)
print_status "Deploying certificate stack to us-east-1..."
npx cdk deploy ResumeBotCertificateStack --require-approval never

# Get the certificate ARN from the certificate stack
print_status "Getting certificate ARN..."
CERT_ARN=$(aws cloudformation describe-stacks --stack-name ResumeBotCertificateStack --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`CertificateArn`].OutputValue' --output text)

if [ -z "$CERT_ARN" ]; then
    print_error "Failed to get certificate ARN from CloudFormation outputs"
    exit 1
fi

print_status "Certificate ARN: $CERT_ARN"

# Deploy the backend stack (Lambda-based)
print_status "Deploying Lambda backend stack..."

# ECR build and image URI setup already completed above
print_status "Ready to deploy with ECR image: $RESUME_BOT_ECR_IMAGE_URI"

print_status "Deploying backend stack..."
print_status "Current environment variables:"
print_status "  CDK_DEFAULT_ACCOUNT: $CDK_DEFAULT_ACCOUNT"
print_status "  CDK_DEFAULT_REGION: $CDK_DEFAULT_REGION"
print_status "  RESUME_BOT_ECR_IMAGE_URI: ${RESUME_BOT_ECR_IMAGE_URI:-'NOT SET'}"

# Show what CDK will see
print_status "Running CDK deployment..."
npx cdk deploy ResumeBotBackendStack --require-approval never

# Construct the backend API URL using the static pattern
print_status "Constructing backend API URL..."
if [ -z "$DOMAIN_NAME" ]; then
    print_error "DOMAIN_NAME environment variable is not set"
    print_warning "Please set DOMAIN_NAME in your .env file"
    exit 1
fi

API_URL="https://api.resume.$DOMAIN_NAME"
print_status "Backend API URL: $API_URL"

# Build the frontend with the correct API URL using the build script
print_status "Building the frontend with backend API URL..."

# Use the frontend build script with the API URL
VITE_API_URL=$API_URL ../resume-bot-frontend/scripts/build.sh

# Check if build was successful
if [ ! -d "../resume-bot-frontend/dist" ]; then
    print_error "Frontend build failed - dist directory not found"
    exit 1
fi

print_status "Frontend build completed successfully with API URL: $API_URL"

# Go back to CDK directory
cd ../resume-bot-deploy

# Deploy the frontend stack with certificate ARN
print_status "Deploying frontend stack with certificate ARN..."
npx cdk deploy ResumeBotFrontendStack --parameters CertificateArnParam="$CERT_ARN" --require-approval never

print_status "🎉 Deployment completed successfully!"
print_warning "Check the CloudFormation outputs for:"
print_warning "- Backend API endpoint URL"
print_warning "- Frontend website URL"
