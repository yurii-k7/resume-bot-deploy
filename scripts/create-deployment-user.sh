#!/bin/bash

# Resume Bot - Create Deployment IAM User with Limited Permissions
# This script creates an IAM user with minimal permissions for CI/CD deployment
# It can only perform Lambda image updates and ECR operations for the resume-bot project

set -e

# Change to the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")"

# Configuration
USER_NAME="resume-bot-deploy-user"
POLICY_NAME="ResumeBotDeploymentPolicy"
AWS_REGION=${AWS_REGION:-"ca-central-1"}
ECR_REPOSITORY="resume-bot/backend-lambda"
LAMBDA_FUNCTION_NAME="resume-bot-backend"
S3_FRONTEND_BUCKET=""  # Will be set dynamically from CloudFormation stack

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
    echo -e "${BLUE}🔐 Resume Bot Deployment User Setup${NC}"
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
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        print_info "  Ubuntu/Debian: sudo apt-get install jq"
        print_info "  macOS: brew install jq"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured or credentials are invalid."
        print_info "Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    print_info "AWS Region: ${AWS_REGION}"
    
    # Get S3 frontend bucket name from CloudFormation stack
    print_info "Getting S3 frontend bucket name from CloudFormation..."
    S3_FRONTEND_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name ResumeBotFrontendStack \
        --region ${AWS_REGION} \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$S3_FRONTEND_BUCKET" ]; then
        print_warning "Could not get S3 bucket name from ResumeBotFrontendStack"
        print_warning "The deployment user will be created without S3 permissions"
        print_warning "Deploy the frontend stack first, then recreate the deployment user"
        S3_FRONTEND_BUCKET="BUCKET_NOT_FOUND"
    else
        print_info "S3 Frontend Bucket: ${S3_FRONTEND_BUCKET}"
    fi
    
    print_success "Prerequisites check passed"
    echo
}

# Create IAM policy with minimal permissions
create_iam_policy() {
    print_info "Creating IAM policy with minimal permissions..."
    
    # Create policy document
    # Build S3 policy section conditionally
    if [ "$S3_FRONTEND_BUCKET" != "BUCKET_NOT_FOUND" ] && [ ! -z "$S3_FRONTEND_BUCKET" ]; then
        S3_POLICY_SECTION="{
            \"Sid\": \"S3FrontendDeployment\",
            \"Effect\": \"Allow\",
            \"Action\": [
                \"s3:GetObject\",
                \"s3:PutObject\",
                \"s3:DeleteObject\",
                \"s3:ListBucket\",
                \"s3:GetBucketLocation\",
                \"s3:PutObjectAcl\"
            ],
            \"Resource\": [
                \"arn:aws:s3:::${S3_FRONTEND_BUCKET}\",
                \"arn:aws:s3:::${S3_FRONTEND_BUCKET}/*\"
            ]
        },"
    else
        S3_POLICY_SECTION=""
        print_warning "Skipping S3 frontend permissions (bucket name not found)"
    fi

    POLICY_DOCUMENT=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECRTokenGeneration",
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECRRepositoryAccess",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:DescribeRepositories",
                "ecr:DescribeImages",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "ecr:CreateRepository"
            ],
            "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${ECR_REPOSITORY}"
        },
        {
            "Sid": "LambdaFunctionUpdate",
            "Effect": "Allow",
            "Action": [
                "lambda:UpdateFunctionCode",
                "lambda:GetFunction",
                "lambda:GetFunctionConfiguration"
            ],
            "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
        },
        ${S3_POLICY_SECTION}
        {
            "Sid": "STSGetCallerIdentity",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" > /dev/null 2>&1; then
        print_warning "Policy ${POLICY_NAME} already exists. Updating..."
        
        # Create a new policy version
        aws iam create-policy-version \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" \
            --policy-document "$POLICY_DOCUMENT" \
            --set-as-default > /dev/null
            
        print_success "Policy updated successfully"
    else
        # Create new policy
        aws iam create-policy \
            --policy-name "${POLICY_NAME}" \
            --policy-document "$POLICY_DOCUMENT" \
            --description "Minimal permissions for Resume Bot CI/CD deployment - ECR, Lambda, and S3 frontend" > /dev/null
            
        print_success "Policy created successfully"
    fi
    
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    echo
}

# Create IAM user
create_iam_user() {
    print_info "Creating IAM user: ${USER_NAME}..."
    
    # Check if user already exists
    if aws iam get-user --user-name "${USER_NAME}" > /dev/null 2>&1; then
        print_warning "User ${USER_NAME} already exists. Continuing with existing user..."
    else
        # Create new user
        aws iam create-user \
            --user-name "${USER_NAME}" \
            --tags Key=Purpose,Value=ResumeBotDeployment Key=Project,Value=ResumeBot > /dev/null
            
        print_success "User created successfully"
    fi
    
    # Attach policy to user
    print_info "Attaching policy to user..."
    aws iam attach-user-policy \
        --user-name "${USER_NAME}" \
        --policy-arn "${POLICY_ARN}"
        
    print_success "Policy attached to user"
    echo
}

# Generate access keys
generate_access_keys() {
    print_info "Generating new access keys..."
    
    # Delete existing access keys first (limit is 2 per user)
    print_info "Checking for existing access keys..."
    EXISTING_KEYS=$(aws iam list-access-keys --user-name "${USER_NAME}" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$EXISTING_KEYS" ] && [ "$EXISTING_KEYS" != "None" ]; then
        print_warning "Found existing access keys. Deleting them..."
        for key in $EXISTING_KEYS; do
            if [ "$key" != "None" ] && [ ! -z "$key" ]; then
                aws iam delete-access-key --user-name "${USER_NAME}" --access-key-id "$key"
                print_info "Deleted access key: ${key}"
            fi
        done
    else
        print_info "No existing access keys found"
    fi
    
    # Create new access key
    print_info "Creating new access key..."
    
    # Use temporary file to avoid command substitution issues
    TEMP_FILE="/tmp/aws_access_key_$$.json"
    aws iam create-access-key --user-name "${USER_NAME}" --output json > "$TEMP_FILE"
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ] || [ ! -f "$TEMP_FILE" ]; then
        print_error "Failed to create access key (exit code: $EXIT_CODE)"
        rm -f "$TEMP_FILE"
        exit 1
    fi
    
    # Parse the JSON output with error checking
    ACCESS_KEY_ID=$(jq -r '.AccessKey.AccessKeyId' "$TEMP_FILE" 2>/dev/null)
    SECRET_ACCESS_KEY=$(jq -r '.AccessKey.SecretAccessKey' "$TEMP_FILE" 2>/dev/null)
    
    # Clean up temporary file
    rm -f "$TEMP_FILE"
    
    if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ] || [ "$ACCESS_KEY_ID" = "null" ] || [ "$SECRET_ACCESS_KEY" = "null" ]; then
        print_error "Failed to parse access key from AWS response"
        exit 1
    fi
    
    print_success "New access keys generated successfully"
    echo
}

# Display results and instructions
display_results() {
    print_success "🎉 Deployment user setup completed!"
    echo
    echo "=================================================="
    echo -e "${GREEN}📋 DEPLOYMENT CREDENTIALS${NC}"
    echo "=================================================="
    echo -e "${YELLOW}AWS_ACCESS_KEY_ID:${NC}     ${ACCESS_KEY_ID}"
    echo -e "${YELLOW}AWS_SECRET_ACCESS_KEY:${NC} ${SECRET_ACCESS_KEY}"
    echo -e "${YELLOW}AWS_REGION:${NC}            ${AWS_REGION}"
    echo "=================================================="
    echo
    
    print_info "🔒 Security Information:"
    echo "   • User: ${USER_NAME}"
    echo "   • Policy: ${POLICY_NAME}"
    echo "   • Permissions: ECR + Lambda + S3 frontend"
    echo "   • ECR Repository: ${ECR_REPOSITORY}"
    echo "   • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "   • S3 Frontend Bucket: ${S3_FRONTEND_BUCKET}"
    echo
    
    print_info "📝 GitHub Secrets Setup:"
    echo "   1. Go to your GitHub repository"
    echo "   2. Navigate to Settings → Secrets and variables → Actions"
    echo "   3. Add these repository secrets:"
    echo "      • AWS_ACCESS_KEY_ID: ${ACCESS_KEY_ID}"
    echo "      • AWS_SECRET_ACCESS_KEY: ${SECRET_ACCESS_KEY}"
    echo "   4. Optionally add repository variable:"
    echo "      • AWS_REGION: ${AWS_REGION}"
    echo
    
    print_warning "⚠️  Security Recommendations:"
    echo "   • Store these credentials securely"
    echo "   • Never commit them to your repository"
    echo "   • Rotate them periodically"
    echo "   • Monitor usage through CloudTrail"
    echo
    
    print_info "🗑️  To clean up later, run:"
    echo "   aws iam detach-user-policy --user-name ${USER_NAME} --policy-arn ${POLICY_ARN}"
    echo "   aws iam delete-access-key --user-name ${USER_NAME} --access-key-id ${ACCESS_KEY_ID}"
    echo "   aws iam delete-user --user-name ${USER_NAME}"
    echo "   aws iam delete-policy --policy-arn ${POLICY_ARN}"
    echo
}

# Main execution
main() {
    print_header
    check_prerequisites
    create_iam_policy
    create_iam_user
    generate_access_keys
    display_results
}

# Run the script
main "$@"