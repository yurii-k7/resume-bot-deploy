#!/bin/bash

# Fix the S3 bucket policy issue that's preventing stack deletion

echo "🔧 Fixing S3 bucket policy to allow stack deletion..."

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "ca-central-1")
BUCKET_NAME="resume-bot-frontend-${ACCOUNT_ID}-${REGION}"

echo "📍 Account ID: $ACCOUNT_ID"
echo "📍 Region: $REGION"
echo "📍 Bucket name: $BUCKET_NAME"

# Check if bucket exists
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "❌ Bucket $BUCKET_NAME does not exist"
    exit 1
fi

echo "✅ Bucket exists: $BUCKET_NAME"

# Step 1: Remove the bucket policy entirely
echo ""
echo "🗑️  Step 1: Removing bucket policy..."
aws s3api delete-bucket-policy --bucket "$BUCKET_NAME"

if [ $? -eq 0 ]; then
    echo "✅ Bucket policy removed successfully"
else
    echo "⚠️  Failed to remove bucket policy (it might not exist)"
fi

# Step 2: Empty the bucket
echo ""
echo "🧹 Step 2: Emptying bucket contents..."
aws s3 rm "s3://$BUCKET_NAME" --recursive

if [ $? -eq 0 ]; then
    echo "✅ Bucket emptied successfully"
else
    echo "⚠️  Failed to empty bucket or bucket was already empty"
fi

# Step 3: Try to delete the stack again
echo ""
echo "🗑️  Step 3: Attempting to delete the CloudFormation stack..."
aws cloudformation delete-stack --stack-name "ResumeBotFrontendStack"

if [ $? -eq 0 ]; then
    echo "✅ Stack deletion initiated successfully"
    echo "⏳ Waiting for stack deletion to complete..."
    
    # Wait for deletion with timeout
    timeout 300 aws cloudformation wait stack-delete-complete --stack-name "ResumeBotFrontendStack"
    
    if [ $? -eq 0 ]; then
        echo "🎉 Stack deleted successfully!"
    else
        echo "⏳ Stack deletion is taking longer than expected. Check AWS Console for status."
    fi
else
    echo "❌ Failed to initiate stack deletion"
fi

# Step 4: Clean up bucket if it still exists
echo ""
echo "🧹 Step 4: Final cleanup check..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "⚠️  Bucket still exists. Attempting manual deletion..."
    aws s3 rb "s3://$BUCKET_NAME" --force
    
    if [ $? -eq 0 ]; then
        echo "✅ Bucket deleted manually"
    else
        echo "❌ Failed to delete bucket. You may need to delete it manually from S3 console"
        echo "   Bucket name: $BUCKET_NAME"
    fi
else
    echo "✅ Bucket successfully removed"
fi

echo ""
echo "🎉 Cleanup process completed!"
echo ""
echo "💡 If you still have issues:"
echo "   1. Go to AWS CloudFormation Console"
echo "   2. Find ResumeBotFrontendStack"
echo "   3. Delete it manually and retain any failing resources"
echo "   4. Then manually delete those resources from their respective consoles"
