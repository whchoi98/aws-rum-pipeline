import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export interface S3DataLakeProps {
  projectName: string;
  rawExpirationDays?: number;
  errorExpirationDays?: number;
}

export class S3DataLake extends Construct {
  public readonly bucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: S3DataLakeProps) {
    super(scope, id);

    const { projectName, rawExpirationDays = 90, errorExpirationDays = 30 } = props;

    this.bucket = new s3.Bucket(this, 'Bucket', {
      bucketName: `${projectName}-data-lake-${cdk.Aws.ACCOUNT_ID}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      bucketKeyEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [
        {
          id: 'noncurrent-cleanup',
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'raw-expiration',
          prefix: 'raw/',
          expiration: cdk.Duration.days(rawExpirationDays),
        },
        {
          id: 'aggregated-tiering',
          prefix: 'aggregated/',
          transitions: [
            { storageClass: s3.StorageClass.INFREQUENT_ACCESS, transitionAfter: cdk.Duration.days(90) },
            { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(365) },
          ],
        },
        {
          id: 'errors-expiration',
          prefix: 'errors/',
          expiration: cdk.Duration.days(errorExpirationDays),
        },
      ],
    });
  }
}
