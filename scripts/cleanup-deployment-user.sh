#!/bin/bash

# Resume Bot - Cleanup Deployment IAM User
# This script removes the deployment IAM user and associated resources

set -e

# Change to the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")"

# Configuration
USER_NAME="resume-bot-deploy-user"
POLICY_NAME="ResumeBotDeploymentPolicy"

# Global variables to be set by check_prerequisites
AWS_ACCOUNT_ID=""

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

print_header() {
    echo -e "${RED}🗑️  Resume Bot Deployment User Cleanup${NC}"
    echo "=================================================="
    echo
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured or credentials are invalid."
        print_info "Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account ID and make it globally available
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID
    print_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    print_success "Prerequisites check passed"
    echo
}

# Confirm cleanup
confirm_cleanup() {
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the deployment user and policy!${NC}"
    echo
    echo "This will remove:"
    echo "  • IAM User: ${USER_NAME}"
    echo "  • IAM Policy: ${POLICY_NAME}"
    echo "  • All access keys for the user"
    echo
    print_warning "Your GitHub Actions will stop working after this cleanup!"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        print_info "Cleanup cancelled by user."
        exit 0
    fi
    echo
}

# Cleanup user resources
cleanup_user() {
    print_info "Cleaning up IAM user: ${USER_NAME}..."
    
    # Check if user exists
    if ! aws iam get-user --user-name "${USER_NAME}" > /dev/null 2>&1; then
        print_warning "User ${USER_NAME} does not exist. Skipping user cleanup."
        return 0
    fi
    
    # Delete all access keys
    print_info "Deleting access keys..."
    EXISTING_KEYS=$(aws iam list-access-keys --user-name "${USER_NAME}" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true)
    
    if [ ! -z "$EXISTING_KEYS" ]; then
        for key in $EXISTING_KEYS; do
            aws iam delete-access-key --user-name "${USER_NAME}" --access-key-id "$key"
            print_info "Deleted access key: ${key}"
        done
        print_success "All access keys deleted"
    else
        print_info "No access keys found"
    fi
    
    # Detach policies from user
    print_info "Detaching policies from user..."
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if policy is attached
    if aws iam list-attached-user-policies --user-name "${USER_NAME}" --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}']" --output text | grep -q "${POLICY_NAME}"; then
        aws iam detach-user-policy --user-name "${USER_NAME}" --policy-arn "${POLICY_ARN}"
        print_success "Policy detached from user"
    else
        print_info "Policy was not attached to user"
    fi
    
    # Delete user
    aws iam delete-user --user-name "${USER_NAME}"
    print_success "User deleted successfully"
    echo
}

# Cleanup policy
cleanup_policy() {
    print_info "Cleaning up IAM policy: ${POLICY_NAME}..."
    
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if policy exists
    if ! aws iam get-policy --policy-arn "${POLICY_ARN}" > /dev/null 2>&1; then
        print_warning "Policy ${POLICY_NAME} does not exist. Skipping policy cleanup."
        return 0
    fi
    
    # Check if policy is attached to any other entities
    print_info "Checking policy attachments..."
    
    # Check users
    ATTACHED_USERS=$(aws iam list-entities-for-policy --policy-arn "${POLICY_ARN}" --query 'PolicyUsers[].UserName' --output text 2>/dev/null || true)
    # Check roles
    ATTACHED_ROLES=$(aws iam list-entities-for-policy --policy-arn "${POLICY_ARN}" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null || true)
    # Check groups
    ATTACHED_GROUPS=$(aws iam list-entities-for-policy --policy-arn "${POLICY_ARN}" --query 'PolicyGroups[].GroupName' --output text 2>/dev/null || true)
    
    if [ ! -z "$ATTACHED_USERS" ] || [ ! -z "$ATTACHED_ROLES" ] || [ ! -z "$ATTACHED_GROUPS" ]; then
        print_warning "Policy is still attached to other entities:"
        [ ! -z "$ATTACHED_USERS" ] && echo "  Users: $ATTACHED_USERS"
        [ ! -z "$ATTACHED_ROLES" ] && echo "  Roles: $ATTACHED_ROLES"
        [ ! -z "$ATTACHED_GROUPS" ] && echo "  Groups: $ATTACHED_GROUPS"
        print_warning "Skipping policy deletion to avoid breaking other resources."
        return 0
    fi
    
    # Delete all non-default policy versions first
    print_info "Deleting policy versions..."
    VERSIONS=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null || true)
    
    if [ ! -z "$VERSIONS" ]; then
        for version in $VERSIONS; do
            aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "$version"
            print_info "Deleted policy version: ${version}"
        done
    fi
    
    # Delete the policy
    aws iam delete-policy --policy-arn "${POLICY_ARN}"
    print_success "Policy deleted successfully"
    echo
}

# Display completion message
display_completion() {
    print_success "🎉 Cleanup completed successfully!"
    echo
    print_warning "📝 Remember to:"
    echo "   • Remove AWS secrets from your GitHub repository"
    echo "   • Update any documentation referencing the deleted user"
    echo "   • Create new deployment credentials if needed later"
    echo
    print_info "To recreate the deployment user, run:"
    echo "   ./create-deployment-user.sh"
    echo
}

# Main execution
main() {
    print_header
    check_prerequisites
    confirm_cleanup
    cleanup_user
    cleanup_policy
    display_completion
}

# Run the script
main "$@"