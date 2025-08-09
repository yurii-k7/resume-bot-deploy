#!/usr/bin/env node
import 'source-map-support/register';
import * as dotenv from 'dotenv';
import * as cdk from 'aws-cdk-lib';

// Load environment variables from .env file
dotenv.config();
import { ResumeBotFrontendStack } from '../lib/resume-bot-frontend-stack';
import { ResumeBotBackendStack } from '../lib/resume-bot-backend-stack';
import { CertificateStack } from '../lib/certificate-stack';

const app = new cdk.App();

// Certificate stack must be deployed to us-east-1 for CloudFront
const certStack = new CertificateStack(app, 'ResumeBotCertificateStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'us-east-1', // Fixed region for CloudFront certificates
  },
  description: 'Resume Bot SSL Certificate for CloudFront (us-east-1)'
});

new ResumeBotBackendStack(app, 'ResumeBotBackendStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Resume Bot Backend - ECS Fargate service with ALB'
});

new ResumeBotFrontendStack(app, 'ResumeBotFrontendStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Resume Bot Frontend - CloudFront distribution with S3 origin'
});
