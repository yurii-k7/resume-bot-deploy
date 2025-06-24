# Resume Bot CDK Deployment

This AWS CDK project deploys the Resume Bot frontend to AWS using CloudFront and S3.

## Architecture

- **S3 Bucket**: Hosts the static React application files
- **CloudFront Distribution**: Provides global CDN with HTTPS
- **Origin Access Control (OAC)**: Secures S3 bucket access through CloudFront only

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Node.js** (version 18 or later)
3. **AWS CDK CLI** installed globally: `npm install -g aws-cdk`
4. **Frontend built** - the React app must be built before deployment

## Setup

1. Install dependencies:
   ```bash
   cd resume-bot-deploy
   npm install
   ```

2. Bootstrap CDK (first time only):
   ```bash
   npx cdk bootstrap
   ```

## Build and Deploy

1. **Build the frontend first**:
   ```bash
   cd ../resume-bot-frontend
   npm run build
   ```

2. **Deploy the CDK stack**:
   ```bash
   cd ../resume-bot-deploy
   npm run deploy
   ```

## Useful Commands

- `npm run build` - compile TypeScript to JavaScript
- `npm run watch` - watch for changes and compile
- `npm run test` - perform the jest unit tests
- `npm run cdk deploy` - deploy this stack to your default AWS account/region
- `npm run cdk diff` - compare deployed stack with current state
- `npm run cdk synth` - emits the synthesized CloudFormation template
- `npm run destroy` - destroy the deployed stack

## Environment Variables

The stack uses the following environment variables:
- `CDK_DEFAULT_ACCOUNT` - AWS account ID
- `CDK_DEFAULT_REGION` - AWS region

These are automatically set by the CDK CLI.

## Outputs

After deployment, the stack outputs:
- **WebsiteURL**: The CloudFront distribution URL where your app is accessible
- **DistributionId**: CloudFront distribution ID for cache invalidation
- **S3BucketName**: The S3 bucket name hosting the files

## Security Features

- S3 bucket is private with no public access
- CloudFront uses Origin Access Control (OAC) for secure S3 access
- HTTPS redirect enforced
- Proper error handling for SPA routing

## Cost Optimization

- Uses CloudFront Price Class 100 (North America and Europe only)
- Optimized caching policies
- Compression enabled

## Production Considerations

For production deployment, consider:
1. Changing `removalPolicy` to `RETAIN` in the S3 bucket
2. Removing `autoDeleteObjects: true`
3. Adding a custom domain with SSL certificate
4. Setting up proper monitoring and alarms
5. Implementing CI/CD pipeline for automated deployments
