#!/bin/bash

# Resume Bot Full Stack Deployment Script
set -e

echo "🚀 Starting Resume Bot Full Stack Deployment..."

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

# Bootstrap CDK if needed (this is safe to run multiple times)
print_status "Bootstrapping CDK (if needed)..."
npx cdk bootstrap

# Bootstrap us-east-1 for certificate stack
print_status "Bootstrapping us-east-1 for certificate stack..."
npx cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT:-$(aws sts get-caller-identity --query Account --output text)}/us-east-1

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
print_status "Building Docker image for Lambda..."
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

# Build the frontend with the correct API URL
print_status "Building the frontend with backend API URL..."
cd ../resume-bot-frontend

# Check if frontend dependencies are installed
if [ ! -d "node_modules" ]; then
    print_status "Installing frontend dependencies..."
    npm install
fi

# Build the frontend with the API URL
VITE_API_URL=$API_URL npm run build

# Check if build was successful
if [ ! -d "dist" ]; then
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
