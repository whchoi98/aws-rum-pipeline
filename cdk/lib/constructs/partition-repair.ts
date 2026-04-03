import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';
import { createPipelineLambda, glueReadPolicy, athenaExecPolicy } from './helpers';

export interface PartitionRepairProps {
  projectName: string;
  glueDatabaseName: string;
  glueTableName: string;
  athenaWorkgroup: string;
  s3Bucket: s3.IBucket;
  lambdaSourceDir: string;
  schedule?: string;
}

export class PartitionRepair extends Construct {
  constructor(scope: Construct, id: string, props: PartitionRepairProps) {
    super(scope, id);

    const {
      projectName, glueDatabaseName, glueTableName,
      athenaWorkgroup, s3Bucket, lambdaSourceDir,
      schedule = 'rate(15 minutes)',
    } = props;

    const fn = createPipelineLambda(this, 'Function', {
      projectName,
      nameSuffix: 'partition-repair',
      sourceDir: lambdaSourceDir,
      timeout: cdk.Duration.seconds(120),
      environment: {
        GLUE_DATABASE: glueDatabaseName,
        GLUE_TABLE: glueTableName,
        ATHENA_WORKGROUP: athenaWorkgroup,
      },
    });

    fn.addToRolePolicy(athenaExecPolicy(this, athenaWorkgroup, [
      'athena:StartQueryExecution', 'athena:GetQueryExecution', 'athena:GetQueryResults',
    ]));
    fn.addToRolePolicy(glueReadPolicy(this, glueDatabaseName, [
      'glue:GetTable', 'glue:GetPartitions', 'glue:BatchCreatePartition', 'glue:CreatePartition',
    ]));
    s3Bucket.grantRead(fn, 'raw/*');
    s3Bucket.grantReadWrite(fn, 'athena-results/*');

    const rule = new events.Rule(this, 'ScheduleRule', {
      ruleName: `${projectName}-partition-repair`,
      schedule: events.Schedule.expression(schedule),
    });
    rule.addTarget(new targets.LambdaFunction(fn));
  }
}
