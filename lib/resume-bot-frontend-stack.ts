import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53targets from 'aws-cdk-lib/aws-route53-targets';
import { Construct } from 'constructs';
import * as path from 'path';

export interface ResumeBotFrontendStackProps extends cdk.StackProps {
  certificateArn?: string;
}

export class ResumeBotFrontendStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: ResumeBotFrontendStackProps) {
    super(scope, id, props);

    // Add parameter for certificate ARN
    const certificateArnParam = new cdk.CfnParameter(this, 'CertificateArnParam', {
      type: 'String',
      description: 'ARN of the SSL certificate in us-east-1 for CloudFront',
      default: '',
    });

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

    // Domain configuration
    const hostedZoneName = process.env.DOMAIN_NAME;
    if (!hostedZoneName) {
      throw new Error('DOMAIN_NAME environment variable is required but not set');
    }
    const domainName = `resume.${hostedZoneName}`;

    // Import existing hosted zone
    const hostedZone = route53.HostedZone.fromLookup(this, 'HostedZone', {
      domainName: hostedZoneName,
    });

    // Create SSL certificate with DNS validation
    // CDK will automatically create this in us-east-1 for use with CloudFront
    let certificate: certificatemanager.ICertificate;
    
    const certArn = certificateArnParam.valueAsString;
    
    if (props?.certificateArn || certArn) {
      // Use provided certificate ARN (must be in us-east-1)
      certificate = certificatemanager.Certificate.fromCertificateArn(
        this, 
        'Certificate', 
        props?.certificateArn || certArn
      );
    } else {
      // Create new certificate - CDK automatically creates certificates for CloudFront in us-east-1
      // This stack must be deployed to us-east-1 for certificate creation to work
      certificate = new certificatemanager.Certificate(this, 'Certificate', {
        domainName: domainName,
        validation: certificatemanager.CertificateValidation.fromDns(hostedZone),
      });
    }

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
      domainNames: [domainName],
      certificate: certificate,
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

    // Create Route53 A record pointing to CloudFront distribution
    new route53.ARecord(this, 'AliasRecord', {
      recordName: domainName,
      target: route53.RecordTarget.fromAlias(new route53targets.CloudFrontTarget(distribution)),
      zone: hostedZone,
    });

    // Outputs
    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: `https://${domainName}`,
      description: 'URL of the Resume Bot frontend',
    });

    new cdk.CfnOutput(this, 'CloudFrontURL', {
      value: `https://${distribution.domainName}`,
      description: 'CloudFront distribution URL',
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront Distribution ID',
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: websiteBucket.bucketName,
      description: 'S3 Bucket name for the website',
    });

    new cdk.CfnOutput(this, 'CertificateArn', {
      value: certificate.certificateArn,
      description: 'SSL Certificate ARN',
    });

    new cdk.CfnOutput(this, 'DomainName', {
      value: domainName,
      description: 'Custom domain name',
    });
  }
}
