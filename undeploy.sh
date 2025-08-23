#!/bin/bash

# Resume Bot Undeploy Script
set -e

# Change to the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "🗑️  Destroying Resume Bot stacks..."

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

# Set dummy ECR image URI for stack destruction (required for CDK stack instantiation)
export RESUME_BOT_ECR_IMAGE_URI="123456789012.dkr.ecr.ca-central-1.amazonaws.com/resume-bot/backend-lambda:dummy-for-destroy"

# Build CDK TypeScript (needed for destroy)
print_status "Building CDK TypeScript..."
npm run build

# Destroy stacks in reverse order of deployment
print_status "Destroying frontend stack..."
npx cdk destroy ResumeBotFrontendStack --force

print_status "Destroying backend stack..."
npx cdk destroy ResumeBotBackendStack --force

# Destroy certificate stack last (in us-east-1)
print_status "Destroying certificate stack from us-east-1..."
npx cdk destroy ResumeBotCertificateStack --force

print_status "🎉 All stacks destroyed successfully!"
print_warning "Note: S3 buckets may have been retained if they contained files"