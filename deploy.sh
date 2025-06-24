#!/bin/bash

# Resume Bot Frontend Deployment Script
set -e

echo "🚀 Starting Resume Bot Frontend Deployment..."

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

# Build the frontend
print_status "Building the frontend..."
cd ../resume-bot-frontend

# Check if frontend dependencies are installed
if [ ! -d "node_modules" ]; then
    print_status "Installing frontend dependencies..."
    npm install
fi

# Build the frontend
npm run build

# Check if build was successful
if [ ! -d "dist" ]; then
    print_error "Frontend build failed - dist directory not found"
    exit 1
fi

print_status "Frontend build completed successfully"

# Go back to CDK directory
cd ../resume-bot-deploy

# Build CDK TypeScript
print_status "Building CDK TypeScript..."
npm run build

# Bootstrap CDK if needed (this is safe to run multiple times)
print_status "Bootstrapping CDK (if needed)..."
npx cdk bootstrap

# Deploy the stack
print_status "Deploying CDK stack..."
npx cdk deploy --require-approval never

print_status "🎉 Deployment completed successfully!"
print_warning "Check the CloudFormation outputs for your website URL"
