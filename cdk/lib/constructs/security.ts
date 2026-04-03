import * as cdk from 'aws-cdk-lib';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';
import { createPipelineLambda } from './helpers';

export interface SecurityProps {
  projectName: string;
  environment: string;
  lambdaSourceDir: string;
  rateLimit?: number;
}

export class Security extends Construct {
  public readonly authorizerFunction: lambda.IFunction;
  public readonly wafAclArn: string;
  public readonly apiKeySsmName: string;

  constructor(scope: Construct, id: string, props: SecurityProps) {
    super(scope, id);

    const { projectName, environment, lambdaSourceDir, rateLimit = 2000 } = props;

    const wafAcl = new wafv2.CfnWebACL(this, 'WafAcl', {
      name: `${projectName}-waf`,
      scope: 'REGIONAL',
      defaultAction: { allow: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: `${projectName}-waf`,
        sampledRequestsEnabled: true,
      },
      rules: [
        {
          name: 'RateLimit',
          priority: 1,
          action: { block: {} },
          statement: { rateBasedStatement: { limit: rateLimit, aggregateKeyType: 'IP' } },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${projectName}-rate-limit`,
            sampledRequestsEnabled: true,
          },
        },
        {
          name: 'BotControl',
          priority: 2,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesBotControlRuleSet',
              managedRuleGroupConfigs: [
                { awsManagedRulesBotControlRuleSet: { inspectionLevel: 'COMMON' } },
              ],
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${projectName}-bot-control`,
            sampledRequestsEnabled: true,
          },
        },
      ],
    });
    this.wafAclArn = wafAcl.attrArn;

    this.apiKeySsmName = `/${projectName}/${environment}/api-keys`;

    // SSM SecureString은 CDK에서 직접 생성 불가 — 배포 후 수동 설정 또는 scripts/setup.sh 사용
    const apiKeyParam = new ssm.StringParameter(this, 'ApiKeyParam', {
      parameterName: this.apiKeySsmName,
      stringValue: 'REPLACE_WITH_SECURE_KEY',
      description: `RUM API Keys (${environment})`,
    });

    this.authorizerFunction = createPipelineLambda(this, 'AuthorizerFunction', {
      projectName,
      nameSuffix: 'authorizer',
      sourceDir: lambdaSourceDir,
      timeout: cdk.Duration.seconds(10),
      environment: { SSM_PARAMETER_NAME: this.apiKeySsmName },
    });

    apiKeyParam.grantRead(this.authorizerFunction);
  }
}
