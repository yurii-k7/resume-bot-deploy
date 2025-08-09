import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as ResumeBotFrontend from '../lib/resume-bot-frontend-stack';

test('S3 Bucket Created', () => {
  // Set required environment variable for test
  process.env.DOMAIN_NAME = 'test.example.com';
  
  const app = new cdk.App();
  // WHEN
  const stack = new ResumeBotFrontend.ResumeBotFrontendStack(app, 'MyTestStack', {
    certificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/test-cert-id'
  });
  // THEN
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::S3::Bucket', {});
});

test('CloudFront Distribution Created', () => {
  // Set required environment variable for test
  process.env.DOMAIN_NAME = 'test.example.com';
  
  const app = new cdk.App();
  // WHEN
  const stack = new ResumeBotFrontend.ResumeBotFrontendStack(app, 'MyTestStack', {
    certificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/test-cert-id'
  });
  // THEN
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::CloudFront::Distribution', {
    DistributionConfig: {
      DefaultRootObject: 'index.html'
    }
  });
});

test('Route53 A Record Created', () => {
  // Set required environment variable for test
  process.env.DOMAIN_NAME = 'test.example.com';
  
  const app = new cdk.App();
  // WHEN
  const stack = new ResumeBotFrontend.ResumeBotFrontendStack(app, 'MyTestStack', {
    certificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/test-cert-id'
  });
  // THEN
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::Route53::RecordSet', {
    Type: 'A',
    Name: `resume.${process.env.DOMAIN_NAME}.`
  });
});
