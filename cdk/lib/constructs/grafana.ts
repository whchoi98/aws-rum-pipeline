import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as grafana from 'aws-cdk-lib/aws-grafana';
import { Construct } from 'constructs';
import { athenaExecPolicy, glueReadPolicy } from './helpers';

export interface GrafanaProps {
  projectName: string;
  s3Bucket: s3.IBucket;
  glueDatabaseName: string;
}

export class Grafana extends Construct {
  public readonly workspaceEndpoint: string;
  public readonly athenaWorkgroupName: string;

  constructor(scope: Construct, id: string, props: GrafanaProps) {
    super(scope, id);

    const { projectName, s3Bucket, glueDatabaseName } = props;

    this.athenaWorkgroupName = `${projectName}-athena`;

    new athena.CfnWorkGroup(this, 'AthenaWorkgroup', {
      name: this.athenaWorkgroupName,
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${s3Bucket.bucketName}/athena-results/`,
        },
        bytesScannedCutoffPerQuery: 100_000_000_000,
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetricsEnabled: true,
      },
    });

    const grafanaRole = new iam.Role(this, 'GrafanaRole', {
      roleName: `${projectName}-grafana-role`,
      assumedBy: new iam.ServicePrincipal('grafana.amazonaws.com'),
    });

    grafanaRole.addToPolicy(athenaExecPolicy(this, this.athenaWorkgroupName, [
      'athena:GetQueryExecution', 'athena:GetQueryResults',
      'athena:StartQueryExecution', 'athena:StopQueryExecution',
      'athena:ListWorkGroups', 'athena:GetWorkGroup',
    ]));

    s3Bucket.grantRead(grafanaRole, 'raw/*');
    s3Bucket.grantRead(grafanaRole, 'aggregated/*');
    s3Bucket.grantReadWrite(grafanaRole, 'athena-results/*');

    grafanaRole.addToPolicy(glueReadPolicy(this, glueDatabaseName, [
      'glue:GetTable', 'glue:GetTables', 'glue:GetDatabase', 'glue:GetDatabases', 'glue:GetPartitions',
    ]));

    const workspace = new grafana.CfnWorkspace(this, 'Workspace', {
      name: `${projectName}-grafana`,
      accountAccessType: 'CURRENT_ACCOUNT',
      authenticationProviders: ['AWS_SSO'],
      permissionType: 'SERVICE_MANAGED',
      dataSources: ['ATHENA'],
      roleArn: grafanaRole.roleArn,
    });

    this.workspaceEndpoint = workspace.attrEndpoint;
  }
}
