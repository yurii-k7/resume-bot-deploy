#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ResumeBotFrontendStack } from '../lib/resume-bot-frontend-stack';

const app = new cdk.App();

new ResumeBotFrontendStack(app, 'ResumeBotFrontendStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Resume Bot Frontend - CloudFront distribution with S3 origin'
});
