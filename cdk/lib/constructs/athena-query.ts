import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';
import { createPipelineLambda, glueReadPolicy, athenaExecPolicy } from './helpers';

export interface AthenaQueryProps {
  projectName: string;
  glueDatabaseName: string;
  athenaWorkgroup: string;
  s3Bucket: s3.IBucket;
  lambdaSourceDir: string;
}

export class AthenaQuery extends Construct {
  public readonly functionName: string;
  public readonly functionArn: string;

  constructor(scope: Construct, id: string, props: AthenaQueryProps) {
    super(scope, id);

    const { projectName, glueDatabaseName, athenaWorkgroup, s3Bucket, lambdaSourceDir } = props;

    const fn = createPipelineLambda(this, 'Function', {
      projectName,
      nameSuffix: 'athena-query',
      sourceDir: lambdaSourceDir,
      memorySize: 256,
      timeout: cdk.Duration.seconds(60),
      environment: {
        GLUE_DATABASE: glueDatabaseName,
        ATHENA_WORKGROUP: athenaWorkgroup,
      },
    });

    fn.addToRolePolicy(athenaExecPolicy(this, athenaWorkgroup));
    fn.addToRolePolicy(glueReadPolicy(this, glueDatabaseName));
    s3Bucket.grantRead(fn, 'raw/*');
    s3Bucket.grantRead(fn, 'aggregated/*');
    s3Bucket.grantReadWrite(fn, 'athena-results/*');

    this.functionName = fn.functionName;
    this.functionArn = fn.functionArn;
  }
}
