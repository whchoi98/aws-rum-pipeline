import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { S3DataLake } from './constructs/s3-data-lake';
import { GlueCatalog } from './constructs/glue-catalog';
import { Firehose } from './constructs/firehose';
import { Security } from './constructs/security';
import { ApiGateway } from './constructs/api-gateway';
import { Monitoring } from './constructs/monitoring';
import { Grafana } from './constructs/grafana';
import { PartitionRepair } from './constructs/partition-repair';
import { AthenaQuery } from './constructs/athena-query';
import { AgentUi } from './constructs/agent-ui';
import { Auth } from './constructs/auth';
import { OpenReplay } from './constructs/openreplay';

export interface RumPipelineStackProps extends cdk.StackProps {
  projectName: string;
  environment: string;
  vpcId?: string;
  publicSubnetIds?: string[];
  privateSubnetIds?: string[];
  agentcoreEndpointArn?: string;
  allowedOrigins?: string[];
  ssoMetadataUrl?: string;
}

export class RumPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RumPipelineStackProps) {
    super(scope, id, props);

    const {
      projectName,
      environment: envName,
      vpcId,
      publicSubnetIds,
      agentcoreEndpointArn,
      allowedOrigins = ['*'],
    } = props;

    // Lambda 소스 경로 (cdk/ 기준 상대 경로)
    const lambdaBase = `${__dirname}/../../lambda`;

    // ─── 1. S3 Data Lake ───
    const dataLake = new S3DataLake(this, 'S3DataLake', {
      projectName,
    });

    // ─── 2. Glue Catalog ───
    const glueCatalog = new GlueCatalog(this, 'GlueCatalog', {
      projectName,
      s3BucketName: dataLake.bucket.bucketName,
    });

    // ─── 3. Firehose ───
    const firehose = new Firehose(this, 'Firehose', {
      projectName,
      s3Bucket: dataLake.bucket,
      glueDatabaseName: glueCatalog.databaseName,
      glueTableName: glueCatalog.eventsTableName,
      lambdaSourceDir: `${lambdaBase}/transform`,
    });

    // ─── 4. Security (WAF + Authorizer) ───
    const security = new Security(this, 'Security', {
      projectName,
      environment: envName,
      lambdaSourceDir: `${lambdaBase}/authorizer`,
    });

    // ─── 5. API Gateway ───
    const apiGw = new ApiGateway(this, 'ApiGateway', {
      projectName,
      firehoseStreamName: firehose.deliveryStreamName,
      firehoseStreamArn: firehose.deliveryStreamArn,
      lambdaSourceDir: `${lambdaBase}/ingest`,
      allowedOrigins,
      authorizerFunction: security.authorizerFunction,
      wafAclArn: security.wafAclArn,
    });

    // ─── 6. Grafana + Athena Workgroup ───
    const grafana = new Grafana(this, 'Grafana', {
      projectName,
      s3Bucket: dataLake.bucket,
      glueDatabaseName: glueCatalog.databaseName,
    });

    // ─── 7. Monitoring ───
    new Monitoring(this, 'Monitoring', {
      projectName,
      apiId: apiGw.apiId,
      firehoseStreamName: firehose.deliveryStreamName,
    });

    // ─── 8. Partition Repair ───
    new PartitionRepair(this, 'PartitionRepair', {
      projectName,
      glueDatabaseName: glueCatalog.databaseName,
      glueTableName: glueCatalog.eventsTableName,
      athenaWorkgroup: grafana.athenaWorkgroupName,
      s3Bucket: dataLake.bucket,
      lambdaSourceDir: `${lambdaBase}/partition-repair`,
    });

    // ─── 9. Athena Query (AgentCore 용) ───
    const athenaQuery = new AthenaQuery(this, 'AthenaQuery', {
      projectName,
      glueDatabaseName: glueCatalog.databaseName,
      athenaWorkgroup: grafana.athenaWorkgroupName,
      s3Bucket: dataLake.bucket,
      lambdaSourceDir: `${lambdaBase}/athena-query`,
    });

    // ─── 10. Agent UI + Auth (선택) ───
    if (vpcId && publicSubnetIds && agentcoreEndpointArn) {
      const agentUi = new AgentUi(this, 'AgentUi', {
        projectName,
        vpcId,
        publicSubnetIds,
        agentcoreEndpointArn,
      });

      // Cognito + Lambda@Edge 인증
      const auth = new Auth(this, 'Auth', {
        projectName,
        cloudfrontDomainName: agentUi.cloudfrontDomainName,
        lambdaSourceDir: `${lambdaBase}/../lambda/edge-auth`,
        ssoMetadataUrl: props.ssoMetadataUrl,
      });

      // CloudFront에 Lambda@Edge 연결은 AgentUi props로 전달
      // 참고: 순환 의존성 때문에 CDK에서는 두 번째 배포에서 연결
      // 또는 agentUi에 직접 edgeAuthFunction 전달

      // ─── 11. OpenReplay Session Replay (선택) ───
      const privateSubnetIds = this.node.tryGetContext('privateSubnetIds') as string[] | undefined;
      if (privateSubnetIds) {
        const openReplay = new OpenReplay(this, 'OpenReplay', {
          projectName,
          environment: envName,
          vpcId,
          publicSubnetIds,
          privateSubnetIds,
        });

        new cdk.CfnOutput(this, 'OpenReplayDashboard', {
          value: `https://${openReplay.cloudfrontDomain}`,
          description: 'OpenReplay Session Replay 대시보드',
        });
      }
    }

    // ─── Outputs ───
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: apiGw.apiEndpoint,
      description: 'RUM API Gateway 엔드포인트',
    });
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: dataLake.bucket.bucketName,
      description: 'S3 Data Lake 버킷',
    });
    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueCatalog.databaseName,
      description: 'Glue 데이터베이스',
    });
    new cdk.CfnOutput(this, 'AthenaWorkgroup', {
      value: grafana.athenaWorkgroupName,
      description: 'Athena 워크그룹',
    });
    new cdk.CfnOutput(this, 'AthenaQueryFunctionName', {
      value: athenaQuery.functionName,
      description: 'Athena Query Lambda (AgentCore 연동)',
    });
  }
}
