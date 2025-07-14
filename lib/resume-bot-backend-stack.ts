import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';
import * as path from 'path';
import * as fs from 'fs';

export class ResumeBotBackendStack extends cdk.Stack {
  public readonly apiEndpoint: string;

  private loadEnvFile(): Record<string, string> {
    const envPath = path.join(__dirname, '../../resume-bot-backend/.env');
    
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

    // Create VPC
    const vpc = new ec2.Vpc(this, 'ResumeBotVPC', {
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public-subnet',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private-subnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
    });

    // Create ECS Cluster
    const cluster = new ecs.Cluster(this, 'ResumeBotCluster', {
      vpc,
      clusterName: 'resume-bot-cluster',
    });

    // Create CloudWatch Log Group
    const logGroup = new logs.LogGroup(this, 'ResumeBotLogGroup', {
      logGroupName: '/aws/ecs/resume-bot-backend',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

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

    // Create Task Definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'ResumeBotTaskDefinition', {
      memoryLimitMiB: 512,
      cpu: 256,
    });

    // Grant task role permission to read secrets
    openaiApiKeySecret.grantRead(taskDefinition.taskRole);
    pineconeApiKeySecret.grantRead(taskDefinition.taskRole);
    langsmithApiKeySecret.grantRead(taskDefinition.taskRole);

    // Add container to task definition
    const container = taskDefinition.addContainer('resume-bot-container', {
      image: ecs.ContainerImage.fromAsset(path.join(__dirname, '../../resume-bot-backend')),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'resume-bot-backend',
        logGroup: logGroup,
      }),
      environment: {
        // Non-sensitive environment variables
        FLASK_ENV: 'production',
        INDEX_NAME: envVars.INDEX_NAME || 'medium-blogs-embeddings-index',
        LANGSMITH_TRACING: envVars.LANGSMITH_TRACING || 'true',
        LANGSMITH_ENDPOINT: envVars.LANGSMITH_ENDPOINT || 'https://api.smith.langchain.com',
        LANGCHAIN_PROJECT: envVars.LANGCHAIN_PROJECT || 'Medium Analyzer',
      },
      secrets: {
        // Sensitive environment variables from AWS Secrets Manager
        OPENAI_API_KEY: ecs.Secret.fromSecretsManager(openaiApiKeySecret),
        PINECONE_API_KEY: ecs.Secret.fromSecretsManager(pineconeApiKeySecret),
        LANGSMITH_API_KEY: ecs.Secret.fromSecretsManager(langsmithApiKeySecret),
      },
    });

    // Add port mapping
    container.addPortMappings({
      containerPort: 8081,
      protocol: ecs.Protocol.TCP,
    });

    // Create Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'ResumeBotALB', {
      vpc,
      internetFacing: true,
      loadBalancerName: 'resume-bot-alb',
    });

    // Create Target Group
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'ResumeBotTargetGroup', {
      port: 8081,
      protocol: elbv2.ApplicationProtocol.HTTP,
      vpc,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        path: '/',
        healthyHttpCodes: '200',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Create HTTP listener for primary access
    const listener = alb.addListener('ResumeBotHttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create ECS Service
    const service = new ecs.FargateService(this, 'ResumeBotService', {
      cluster,
      taskDefinition,
      serviceName: 'resume-bot-service',
      desiredCount: 1,
      assignPublicIp: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Attach service to target group
    service.attachToApplicationTargetGroup(targetGroup);

    // Allow ALB to access ECS service
    service.connections.allowFrom(alb, ec2.Port.tcp(8081));

    // Create API Gateway to proxy requests to ALB over HTTPS
    const api = new apigateway.RestApi(this, 'ResumeBotApi', {
      restApiName: 'Resume Bot API',
      description: 'API Gateway proxy for Resume Bot backend',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
    });

    // Create integration with ALB
    const integration = new apigateway.HttpIntegration(`http://${alb.loadBalancerDnsName}/{proxy}`, {
      httpMethod: 'ANY',
      options: {
        requestParameters: {
          'integration.request.path.proxy': 'method.request.path.proxy',
        },
      },
    });

    // Add proxy resource to handle all requests
    const proxyResource = api.root.addResource('{proxy+}');
    proxyResource.addMethod('ANY', integration, {
      requestParameters: {
        'method.request.path.proxy': true,
      },
    });

    // Add CORS support for the API
    proxyResource.addCorsPreflight({
      allowOrigins: ['*'],
      allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
      allowHeaders: ['Content-Type', 'Authorization'],
    });

    // Set the API endpoint to use API Gateway URL (which provides HTTPS)
    this.apiEndpoint = api.url;

    // Outputs
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'DNS name of the load balancer',
    });

    new cdk.CfnOutput(this, 'APIEndpoint', {
      value: this.apiEndpoint,
      description: 'Resume Bot Backend API endpoint (via API Gateway)',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: service.serviceName,
      description: 'ECS Service name',
    });

  }
}