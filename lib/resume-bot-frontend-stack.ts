import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';
import * as path from 'path';

export class ResumeBotFrontendStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // S3 bucket for hosting static files (not configured as website)
    const websiteBucket = new s3.Bucket(this, 'ResumeBotWebsiteBucket', {
      publicReadAccess: false, // Private bucket, access via CloudFront only
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development - change to RETAIN for production
      autoDeleteObjects: true, // For development - remove for production
    });

    // Origin Access Identity (OAI) - simpler and more reliable than OAC for this use case
    const originAccessIdentity = new cloudfront.OriginAccessIdentity(this, 'OAI', {
      comment: 'Resume Bot Frontend OAI',
    });

    // Note: We don't need to explicitly grant read access here
    // The S3Origin construct will handle the bucket policy automatically

    // CloudFront distribution using L2 construct with OAI
    const distribution = new cloudfront.Distribution(this, 'ResumeBotDistribution', {
      defaultBehavior: {
        origin: new origins.S3Origin(websiteBucket, {
          originAccessIdentity: originAccessIdentity,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
      defaultRootObject: 'index.html',
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.minutes(30),
        },
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.minutes(30),
        },
      ],
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      comment: 'Resume Bot Frontend Distribution',
    });

    // The OAI automatically grants the necessary permissions to the S3 bucket
    // No additional bucket policy needed when using OAI with L2 constructs

    // Deploy the frontend build to S3
    new s3deploy.BucketDeployment(this, 'DeployWebsite', {
      sources: [s3deploy.Source.asset(path.join(__dirname, '../../resume-bot-frontend/dist'))],
      destinationBucket: websiteBucket,
      distribution: distribution,
      distributionPaths: ['/*'],
    });

    // Outputs
    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: `https://${distribution.domainName}`,
      description: 'URL of the Resume Bot frontend',
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront Distribution ID',
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: websiteBucket.bucketName,
      description: 'S3 Bucket name for the website',
    });
  }
}
