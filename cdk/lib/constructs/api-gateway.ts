import * as cdk from 'aws-cdk-lib';
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as integrations from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as authorizers from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { createPipelineLambda } from './helpers';

export interface ApiGatewayProps {
  projectName: string;
  firehoseStreamName: string;
  firehoseStreamArn: string;
  lambdaSourceDir: string;
  allowedOrigins?: string[];
  authorizerFunction?: lambda.IFunction;
  wafAclArn?: string;
}

export class ApiGateway extends Construct {
  public readonly apiEndpoint: string;
  public readonly apiId: string;

  constructor(scope: Construct, id: string, props: ApiGatewayProps) {
    super(scope, id);

    const {
      projectName,
      firehoseStreamName,
      firehoseStreamArn,
      lambdaSourceDir,
      allowedOrigins = ['*'],
      authorizerFunction,
      wafAclArn,
    } = props;

    const ingestFn = createPipelineLambda(this, 'IngestFunction', {
      projectName,
      nameSuffix: 'ingest',
      sourceDir: lambdaSourceDir,
      environment: { FIREHOSE_STREAM_NAME: firehoseStreamName },
    });

    ingestFn.addToRolePolicy(new iam.PolicyStatement({
      actions: ['firehose:PutRecord', 'firehose:PutRecordBatch'],
      resources: [firehoseStreamArn],
    }));

    const httpApi = new apigwv2.HttpApi(this, 'HttpApi', {
      apiName: `${projectName}-api`,
      corsPreflight: {
        allowMethods: [apigwv2.CorsHttpMethod.POST, apigwv2.CorsHttpMethod.OPTIONS],
        allowOrigins: allowedOrigins,
        allowHeaders: ['Content-Type', 'x-api-key', 'x-rum-session'],
      },
    });

    const stage = httpApi.defaultStage?.node.defaultChild as apigwv2.CfnStage;
    if (stage) {
      stage.defaultRouteSettings = {
        throttlingBurstLimit: 1000,
        throttlingRateLimit: 500,
      };
    }

    let httpAuthorizer: apigwv2.IHttpRouteAuthorizer | undefined;
    if (authorizerFunction) {
      httpAuthorizer = new authorizers.HttpLambdaAuthorizer('ApiKeyAuthorizer', authorizerFunction, {
        authorizerName: `${projectName}-api-key-authorizer`,
        responseTypes: [authorizers.HttpLambdaResponseType.SIMPLE],
        identitySource: ['$request.header.x-api-key'],
        resultsCacheTtl: cdk.Duration.seconds(300),
      });
    }

    const lambdaIntegration = new integrations.HttpLambdaIntegration('IngestIntegration', ingestFn);

    for (const path of ['/v1/events', '/v1/events/beacon']) {
      httpApi.addRoutes({
        path,
        methods: [apigwv2.HttpMethod.POST],
        integration: lambdaIntegration,
        authorizer: httpAuthorizer,
      });
    }

    if (wafAclArn) {
      new cdk.aws_wafv2.CfnWebACLAssociation(this, 'WafAssociation', {
        webAclArn: wafAclArn,
        resourceArn: `arn:aws:apigateway:${cdk.Aws.REGION}::/apis/${httpApi.apiId}/stages/$default`,
      });
    }

    this.apiEndpoint = httpApi.apiEndpoint;
    this.apiId = httpApi.apiId;
  }
}
