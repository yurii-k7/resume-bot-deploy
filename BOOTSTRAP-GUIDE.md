# CDK Bootstrap Guide for Resume Bot

## 🚨 Common Bootstrap Error

**Error**: `No ECR repository named 'cdk-hnb659fds-container-assets-058264535337-ca-central-1' in account 058264535337. Is this account bootstrapped?`

**Cause**: CDK needs to be bootstrapped in `ca-central-1` to deploy Docker containers to Lambda.

## 🔧 Quick Fix

### Option 1: Run Bootstrap Script (Recommended)

```bash
cd resume-bot-deploy
./scripts/bootstrap-regions.sh
```

This will bootstrap both required regions:
- `ca-central-1` (for backend Lambda)
- `us-east-1` (for CloudFront certificates)

### Option 2: Manual Bootstrap

```bash
# Get your AWS account ID
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Bootstrap ca-central-1 for backend stack
npx cdk bootstrap aws://$AWS_ACCOUNT/ca-central-1

# Bootstrap us-east-1 for certificate stack
npx cdk bootstrap aws://$AWS_ACCOUNT/us-east-1
```

### Option 3: Use Updated deploy.sh

The updated `deploy.sh` script now automatically bootstraps both regions:

```bash
./deploy.sh
```

## 🏗️ What CDK Bootstrap Does

CDK Bootstrap creates required infrastructure in each region:
- **S3 Bucket**: For CDK assets (CloudFormation templates, Lambda code)
- **ECR Repository**: For Docker container images (`cdk-hnb659fds-container-assets-*`)
- **IAM Roles**: For CDK deployment permissions
- **SSM Parameters**: For storing bootstrap version info

## 🌍 Region Requirements

### ca-central-1 (Your Default Region)
- ✅ Backend Lambda function (Docker container)
- ✅ API Gateway
- ✅ Frontend S3 bucket and CloudFront distribution
- ✅ All other Resume Bot resources

### us-east-1 (Required for CloudFront)
- ✅ SSL Certificate (ACM certificates for CloudFront must be in us-east-1)

## 🔍 Verify Bootstrap Status

Check if regions are bootstrapped:

```bash
# Check ca-central-1
aws cloudformation list-stacks --region ca-central-1 --query 'StackSummaries[?starts_with(StackName, `CDKToolkit`)].{Name:StackName,Status:StackStatus}' --output table

# Check us-east-1  
aws cloudformation list-stacks --region us-east-1 --query 'StackSummaries[?starts_with(StackName, `CDKToolkit`)].{Name:StackName,Status:StackStatus}' --output table
```

Expected output: You should see `CDKToolkit` stacks with `CREATE_COMPLETE` status in both regions.

## 🚀 After Bootstrap

Once bootstrapped, you can deploy Resume Bot:

```bash
# Complete deployment
./deploy.sh

# Or deploy individual stacks
npx cdk deploy ResumeBotBackendStack
npx cdk deploy ResumeBotCertificateStack
npx cdk deploy ResumeBotFrontendStack
```

## 🛡️ Security Notes

- Bootstrap is a **one-time setup** per region per account
- Safe to run multiple times (idempotent)
- Creates minimal required infrastructure
- Uses least-privilege IAM roles
- Can be removed with `npx cdk destroy CDKToolkit` if needed

## 💡 Pro Tips

1. **Set Environment Variables** (optional):
   ```bash
   export CDK_DEFAULT_ACCOUNT=058264535337
   export CDK_DEFAULT_REGION=ca-central-1
   ```

2. **Check Bootstrap Version**:
   ```bash
   npx cdk doctor
   ```

3. **Force Re-bootstrap** (if needed):
   ```bash
   npx cdk bootstrap --force
   ```

## 🔗 Related Files

- `scripts/bootstrap-regions.sh` - Automated bootstrap script
- `deploy.sh` - Main deployment script (now includes bootstrap)
- `bin/resume-bot-deploy.ts` - CDK app configuration with regions