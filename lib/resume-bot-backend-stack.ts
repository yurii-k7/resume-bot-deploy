import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53targets from 'aws-cdk-lib/aws-route53-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as path from 'path';
import * as fs from 'fs';

export class ResumeBotBackendStack extends cdk.Stack {
  public readonly apiEndpoint: string;

  private loadEnvFile(): Record<string, string> {
    const envPath = path.join(__dirname, '../.env');
    
    if (!fs.existsSync(envPath)) {
      throw new Error(`Environment file not found at ${envPath}`);
    }

    const envContent = fs.readFileSync(envPath, 'utf8');
    const envVars: Record<string, string> = {};

    envContent.split('\n').forEach(line => {
      line = line.trim();
      if (line && !line.startsWith('#')) {
        const [key, ...valueParts] = line.split('=');
        if (key && valueParts.length > 0) {
          envVars[key.trim()] = valueParts.join('=').trim();
        }
      }
    });

    return envVars;
  }

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Load environment variables from .env file
    const envVars = this.loadEnvFile();

    // Validate that required environment variables are present
    const requiredEnvVars = ['OPENAI_API_KEY', 'PINECONE_API_KEY', 'LANGSMITH_API_KEY'];
    for (const envVar of requiredEnvVars) {
      if (!envVars[envVar]) {
        throw new Error(`Required environment variable ${envVar} not found in .env file`);
      }
    }

    // Create secrets for sensitive environment variables using actual values from .env
    const openaiApiKeySecret = new secretsmanager.Secret(this, 'OpenAIApiKeySecret', {
      description: 'OpenAI API Key for Resume Bot',
      secretStringValue: cdk.SecretValue.unsafePlainText(envVars.OPENAI_API_KEY),
    });

    const pineconeApiKeySecret = new secretsmanager.Secret(this, 'PineconeApiKeySecret', {
      description: 'Pinecone API Key for Resume Bot',
      secretStringValue: cdk.SecretValue.unsafePlainText(envVars.PINECONE_API_KEY),
    });

    const langsmithApiKeySecret = new secretsmanager.Secret(this, 'LangsmithApiKeySecret', {
      description: 'LangSmith API Key for Resume Bot',
      secretStringValue: cdk.SecretValue.unsafePlainText(envVars.LANGSMITH_API_KEY),
    });

    // Create CloudWatch Log Group for Lambda
    const logGroup = new logs.LogGroup(this, 'ResumeBotLogGroup', {
      logGroupName: '/aws/lambda/resume-bot-backend',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function using Docker container
    // Option 1: Use ECR image URI (recommended for production)
    // Set RESUME_BOT_ECR_IMAGE_URI environment variable to use ECR image
    // Example: 123456789012.dkr.ecr.ca-central-1.amazonaws.com/resume-bot/backend-lambda:backend-20240814-161523-a1b2c3d4
    const ecrImageUri = process.env.RESUME_BOT_ECR_IMAGE_URI;
    
    if (!ecrImageUri) {
      throw new Error('RESUME_BOT_ECR_IMAGE_URI environment variable is required. Please build and push an image to ECR first.');
    }

    // Use ECR image with timestamp-based tag
    console.log(`Using ECR image: ${ecrImageUri}`);
    
    // Parse ECR URI to get repository and tag
    // Expected format: 123456789012.dkr.ecr.ca-central-1.amazonaws.com/resume-bot/backend-lambda:backend-20240814-161523-a1b2c3d4
    console.log(`Parsing ECR URI: ${ecrImageUri}`);
    
    // Split on last ':' to handle registry URLs correctly
    const lastColonIndex = ecrImageUri.lastIndexOf(':');
    const registryAndRepo = ecrImageUri.substring(0, lastColonIndex);
    const tag = ecrImageUri.substring(lastColonIndex + 1);
    const repoName = registryAndRepo.split('/').slice(1).join('/'); // Extract "resume-bot/backend-lambda"
    
    console.log(`Extracted repository name: ${repoName}`);
    console.log(`Extracted tag: ${tag}`);
    
    // Reference the existing ECR repository
    const ecrRepo = ecr.Repository.fromRepositoryName(this, 'ResumeBotEcrRepo', repoName);
    
    const lambdaCode = lambda.DockerImageCode.fromEcr(ecrRepo, {
      tagOrDigest: tag || 'latest',
    });

    const lambdaFunction = new lambda.DockerImageFunction(this, 'ResumeBotLambdaFunction', {
      code: lambdaCode,
      functionName: 'resume-bot-backend',
      timeout: cdk.Duration.minutes(15), // Max timeout for Lambda
      memorySize: 3008, // Max memory for better performance with large dependencies
      environment: {
        // Non-sensitive environment variables
        FLASK_ENV: 'production',
        INDEX_NAME: envVars.INDEX_NAME || 'medium-blogs-embeddings-index',
        LANGSMITH_TRACING: envVars.LANGSMITH_TRACING || 'true',
        LANGSMITH_ENDPOINT: envVars.LANGSMITH_ENDPOINT || 'https://api.smith.langchain.com',
        LANGCHAIN_PROJECT: envVars.LANGCHAIN_PROJECT || 'Medium Analyzer',
        // Lambda-specific environment variables
        PYTHONPATH: '/var/task/src',
        // Add build info for debugging
        BUILD_MODE: 'ECR',
        ECR_IMAGE_URI: ecrImageUri,
      },
    });

    // Grant Lambda permissions to read secrets
    openaiApiKeySecret.grantRead(lambdaFunction);
    pineconeApiKeySecret.grantRead(lambdaFunction);
    langsmithApiKeySecret.grantRead(lambdaFunction);

    // Add environment variables for secret ARNs (Lambda will resolve these at runtime)
    lambdaFunction.addEnvironment('OPENAI_API_KEY_SECRET_ARN', openaiApiKeySecret.secretArn);
    lambdaFunction.addEnvironment('PINECONE_API_KEY_SECRET_ARN', pineconeApiKeySecret.secretArn);
    lambdaFunction.addEnvironment('LANGSMITH_API_KEY_SECRET_ARN', langsmithApiKeySecret.secretArn);

    // Domain configuration for backend API
    const hostedZoneName = process.env.DOMAIN_NAME;
    if (!hostedZoneName) {
      throw new Error('DOMAIN_NAME environment variable is required but not set');
    }
    const apiDomainName = `api.resume.${hostedZoneName}`;

    // Import existing hosted zone
    const hostedZone = route53.HostedZone.fromLookup(this, 'HostedZone', {
      domainName: hostedZoneName,
    });

    // Create SSL certificate for API subdomain
    const apiCertificate = new certificatemanager.Certificate(this, 'ApiCertificate', {
      domainName: apiDomainName,
      validation: certificatemanager.CertificateValidation.fromDns(hostedZone),
    });

    // Create API Gateway
    const api = new apigateway.RestApi(this, 'ResumeBotApi', {
      restApiName: 'Resume Bot API',
      description: 'API Gateway for Resume Bot Lambda backend',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      // Enable request validation but disable logging to avoid CloudWatch role ARN requirement
      deployOptions: {
        stageName: 'prod',
        loggingLevel: apigateway.MethodLoggingLevel.OFF,
        dataTraceEnabled: false,
        metricsEnabled: true,
      },
    });

    // Create Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(lambdaFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true, // Use Lambda proxy integration
    });

    // Add root route (/) to handle all requests
    api.root.addMethod('ANY', lambdaIntegration);

    // Add proxy resource to handle all sub-routes
    const proxyResource = api.root.addResource('{proxy+}');
    proxyResource.addMethod('ANY', lambdaIntegration);

    // Add CORS support
    const corsOptions: apigateway.CorsOptions = {
      allowOrigins: ['*'],
      allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
      allowHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    };

    api.root.addCorsPreflight(corsOptions);
    proxyResource.addCorsPreflight(corsOptions);

    // Create custom domain name for API Gateway
    const apiDomain = new apigateway.DomainName(this, 'ApiDomainName', {
      domainName: apiDomainName,
      certificate: apiCertificate,
      endpointType: apigateway.EndpointType.REGIONAL,
    });

    // Create base path mapping
    new apigateway.BasePathMapping(this, 'BasePathMapping', {
      domainName: apiDomain,
      restApi: api,
    });

    // Create Route53 A record
    new route53.ARecord(this, 'ApiAliasRecord', {
      recordName: apiDomainName,
      target: route53.RecordTarget.fromAlias(
        new route53targets.ApiGatewayDomain(apiDomain)
      ),
      zone: hostedZone,
    });

    // Set the API endpoint
    this.apiEndpoint = `https://${apiDomainName}`;

    // Create CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'ResumeBotDashboard', {
      dashboardName: 'ResumeBot-Lambda-Monitoring',
    });

    // Add Lambda and API Gateway metrics to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda - Invocations',
        left: [lambdaFunction.metricInvocations()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda - Duration',
        left: [lambdaFunction.metricDuration()],
        width: 12,
        height: 6,
      }),
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda - Errors',
        left: [lambdaFunction.metricErrors()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda - Throttles',
        left: [lambdaFunction.metricThrottles()],
        width: 12,
        height: 6,
      }),
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'API Gateway - Request Count',
        left: [api.metricCount()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'API Gateway - Latency',
        left: [api.metricLatency()],
        width: 12,
        height: 6,
      }),
    );

    // Create CloudWatch Alarms
    new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      metric: lambdaFunction.metricErrors(),
      threshold: 5,
      evaluationPeriods: 2,
      alarmDescription: 'High error rate on Resume Bot Lambda',
    });

    new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      metric: api.metricLatency(),
      threshold: 10000, // 10 seconds
      evaluationPeriods: 2,
      alarmDescription: 'High latency on Resume Bot API',
    });

    new cloudwatch.Alarm(this, 'LambdaThrottleAlarm', {
      metric: lambdaFunction.metricThrottles(),
      threshold: 1,
      evaluationPeriods: 1,
      alarmDescription: 'Lambda function is being throttled',
    });

    // Outputs
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: lambdaFunction.functionName,
      description: 'Lambda function name',
    });

    new cdk.CfnOutput(this, 'APIEndpoint', {
      value: this.apiEndpoint,
      description: 'Resume Bot Backend API endpoint (via custom domain)',
    });

    new cdk.CfnOutput(this, 'CustomApiDomain', {
      value: apiDomainName,
      description: 'Custom domain name for the API',
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway URL (direct access)',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for Lambda logs',
    });
  }
}