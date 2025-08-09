import * as cdk from 'aws-cdk-lib';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import { Construct } from 'constructs';

export class CertificateStack extends cdk.Stack {
  public readonly certificate: certificatemanager.ICertificate;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

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

    // Create SSL certificate with DNS validation in us-east-1
    this.certificate = new certificatemanager.Certificate(this, 'Certificate', {
      domainName: domainName,
      validation: certificatemanager.CertificateValidation.fromDns(hostedZone),
    });

    // Output the certificate ARN for use in other stacks
    new cdk.CfnOutput(this, 'CertificateArn', {
      value: this.certificate.certificateArn,
      description: 'SSL Certificate ARN for CloudFront',
      exportName: 'ResumeBotCertificateArn',
    });
  }
}