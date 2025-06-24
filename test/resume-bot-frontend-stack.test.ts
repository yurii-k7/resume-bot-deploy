import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as ResumeBotFrontend from '../lib/resume-bot-frontend-stack';

test('S3 Bucket Created', () => {
  const app = new cdk.App();
  // WHEN
  const stack = new ResumeBotFrontend.ResumeBotFrontendStack(app, 'MyTestStack');
  // THEN
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::S3::Bucket', {
    WebsiteConfiguration: {
      IndexDocument: 'index.html',
      ErrorDocument: 'index.html'
    }
  });
});

test('CloudFront Distribution Created', () => {
  const app = new cdk.App();
  // WHEN
  const stack = new ResumeBotFrontend.ResumeBotFrontendStack(app, 'MyTestStack');
  // THEN
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::CloudFront::Distribution', {
    DistributionConfig: {
      DefaultRootObject: 'index.html'
    }
  });
});

test('Origin Access Control Created', () => {
  const app = new cdk.App();
  // WHEN
  const stack = new ResumeBotFrontend.ResumeBotFrontendStack(app, 'MyTestStack');
  // THEN
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::CloudFront::OriginAccessControl', {
    OriginAccessControlConfig: {
      Name: 'resume-bot-oac',
      OriginAccessControlOriginType: 's3',
      SigningBehavior: 'always',
      SigningProtocol: 'sigv4'
    }
  });
});
