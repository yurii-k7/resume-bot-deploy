#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ResumeBotFrontendStack } from '../lib/resume-bot-frontend-stack';
import { ResumeBotBackendStack } from '../lib/resume-bot-backend-stack';

const app = new cdk.App();

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
