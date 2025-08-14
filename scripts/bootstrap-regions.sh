#!/bin/bash

# Resume Bot CDK Bootstrap Script
# This script bootstraps the required AWS regions for Resume Bot deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info "Resume Bot CDK Bootstrap Script"
echo

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    print_error "AWS CLI is not configured or credentials are invalid"
    print_warning "Please run 'aws configure' to set up your credentials"
    exit 1
fi

# Get AWS account ID and regions
CDK_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
CDK_REGION=${CDK_DEFAULT_REGION:-$(aws configure get region || echo "ca-central-1")}

print_info "AWS Account: $CDK_ACCOUNT"
print_info "Default Region: $CDK_REGION"
echo

# Bootstrap ca-central-1 (for backend stack)
print_info "Bootstrapping $CDK_REGION for Resume Bot backend stack..."
if npx cdk bootstrap aws://$CDK_ACCOUNT/$CDK_REGION; then
    print_success "Successfully bootstrapped $CDK_REGION"
else
    print_error "Failed to bootstrap $CDK_REGION"
    exit 1
fi

echo

# Bootstrap us-east-1 (for certificate stack - required for CloudFront)
print_info "Bootstrapping us-east-1 for Certificate stack (required for CloudFront)..."
if npx cdk bootstrap aws://$CDK_ACCOUNT/us-east-1; then
    print_success "Successfully bootstrapped us-east-1"
else
    print_error "Failed to bootstrap us-east-1"
    exit 1
fi

echo
print_success "🎉 All regions bootstrapped successfully!"
echo
print_info "You can now deploy Resume Bot stacks:"
echo "  • Backend Stack (Lambda): Deploys to $CDK_REGION"
echo "  • Certificate Stack: Deploys to us-east-1 (for CloudFront)"
echo "  • Frontend Stack: Deploys to $CDK_REGION"
echo
print_info "Next steps:"
echo "  1. Run: ./deploy.sh (complete deployment)"
echo "  2. Or run individual deployments as needed"