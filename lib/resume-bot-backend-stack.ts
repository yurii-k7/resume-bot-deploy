import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import * as path from 'path';

export class ResumeBotBackendStack extends cdk.Stack {
  public readonly apiEndpoint: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

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

    // Create Task Definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'ResumeBotTaskDefinition', {
      memoryLimitMiB: 512,
      cpu: 256,
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('resume-bot-container', {
      image: ecs.ContainerImage.fromAsset(path.join(__dirname, '../../resume-bot-backend')),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'resume-bot-backend',
        logGroup: logGroup,
      }),
      environment: {
        FLASK_ENV: 'production',
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

    // Create Listener
    const listener = alb.addListener('ResumeBotListener', {
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

    // Set the API endpoint for cross-stack reference
    this.apiEndpoint = `http://${alb.loadBalancerDnsName}`;

    // Outputs
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'DNS name of the load balancer',
    });

    new cdk.CfnOutput(this, 'APIEndpoint', {
      value: this.apiEndpoint,
      description: 'Resume Bot Backend API endpoint',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: service.serviceName,
      description: 'ECS Service name',
    });
  }
}