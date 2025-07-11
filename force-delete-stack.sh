#!/bin/bash

# Force delete the CloudFormation stack when it's stuck in DELETE_FAILED state

echo "🗑️  Force deleting ResumeBotFrontendStack..."

STACK_NAME="ResumeBotFrontendStack"

# Check if stack exists and its status
echo "📊 Checking stack status..."
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Stack $STACK_NAME not found"
    exit 1
fi

echo "📍 Current stack status: $STACK_STATUS"

if [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
    echo "🔧 Stack is in DELETE_FAILED state. Attempting to continue deletion..."
    
    # Try to continue the deletion, retaining problematic resources
    echo "🔄 Continuing stack deletion (retaining problematic resources)..."
    aws cloudformation continue-update-rollback --stack-name "$STACK_NAME" --resources-to-skip "ResumeBotWebsiteBucketPolicy54B8C173" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Continue rollback initiated. Waiting for completion..."
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
        echo "✅ Rollback completed. Now attempting deletion again..."
    fi
    
    # Try deletion again
    echo "🗑️  Attempting stack deletion..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    
    if [ $? -eq 0 ]; then
        echo "✅ Stack deletion initiated. Waiting for completion..."
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
        echo "🎉 Stack deleted successfully!"
    else
        echo "❌ Stack deletion failed. You may need to:"
        echo "   1. Go to AWS CloudFormation Console"
        echo "   2. Select the stack and choose 'Delete'"
        echo "   3. Check 'Retain' for any problematic resources"
        echo "   4. Manually delete retained resources from their respective consoles"
    fi
    
elif [ "$STACK_STATUS" = "DELETE_IN_PROGRESS" ]; then
    echo "⏳ Stack deletion already in progress. Waiting for completion..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
    echo "🎉 Stack deleted successfully!"
    
else
    echo "🗑️  Initiating normal stack deletion..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    
    if [ $? -eq 0 ]; then
        echo "✅ Stack deletion initiated. Waiting for completion..."
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
        echo "🎉 Stack deleted successfully!"
    else
        echo "❌ Failed to initiate stack deletion"
        exit 1
    fi
fi

# Clean up any remaining S3 bucket manually if needed
echo ""
echo "🧹 Checking for any remaining S3 buckets..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")
BUCKET_NAME="resume-bot-frontend-${ACCOUNT_ID}-${REGION}"

if aws s3 ls "s3://$BUCKET_NAME" > /dev/null 2>&1; then
    echo "⚠️  S3 bucket still exists: $BUCKET_NAME"
    echo "🗑️  Attempting to empty and delete bucket..."
    
    # Empty the bucket first
    aws s3 rm "s3://$BUCKET_NAME" --recursive
    
    # Delete the bucket
    aws s3 rb "s3://$BUCKET_NAME"
    
    if [ $? -eq 0 ]; then
        echo "✅ S3 bucket deleted successfully"
    else
        echo "❌ Failed to delete S3 bucket. You may need to delete it manually from the S3 console"
    fi
else
    echo "✅ No remaining S3 buckets found"
fi

echo ""
echo "🎉 Cleanup completed!"
