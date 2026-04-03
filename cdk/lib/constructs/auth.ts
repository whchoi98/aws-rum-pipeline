import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { LOG_RETENTION } from './helpers';

export interface AuthProps {
  projectName: string;
  cloudfrontDomainName: string;
  lambdaSourceDir: string;
  ssoMetadataUrl?: string;
  ssoProviderName?: string;
}

export class Auth extends Construct {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly edgeFunction: cloudfront.experimental.EdgeFunction;

  constructor(scope: Construct, id: string, props: AuthProps) {
    super(scope, id);

    const {
      projectName,
      cloudfrontDomainName,
      lambdaSourceDir,
      ssoMetadataUrl,
      ssoProviderName = 'AWSSSOProvider',
    } = props;

    const callbackUrl = `https://${cloudfrontDomainName}/auth/callback`;
    const logoutUrl = `https://${cloudfrontDomainName}/`;

    // Cognito User Pool
    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `${projectName}-agent-users`,
      selfSignUpEnabled: false,
      signInAliases: { email: true },
      autoVerify: { email: true },
      standardAttributes: {
        email: { required: true, mutable: true },
      },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Hosted UI 도메인
    this.userPool.addDomain('Domain', {
      cognitoDomain: { domainPrefix: projectName },
    });

    // SSO Identity Provider (조건부)
    const supportedProviders: cognito.UserPoolClientIdentityProvider[] = [];
    if (ssoMetadataUrl) {
      new cognito.UserPoolIdentityProviderSaml(this, 'SSOProvider', {
        userPool: this.userPool,
        name: ssoProviderName,
        metadata: cognito.UserPoolIdentityProviderSamlMetadata.url(ssoMetadataUrl),
        attributeMapping: {
          email: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'),
          fullname: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'),
        },
      });
      supportedProviders.push(cognito.UserPoolClientIdentityProvider.custom(ssoProviderName));
    } else {
      supportedProviders.push(cognito.UserPoolClientIdentityProvider.COGNITO);
    }

    // App Client
    this.userPoolClient = this.userPool.addClient('AppClient', {
      userPoolClientName: `${projectName}-agent-app`,
      generateSecret: false,
      oAuth: {
        flows: { authorizationCodeGrant: true },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: [callbackUrl],
        logoutUrls: [logoutUrl],
      },
      supportedIdentityProviders: supportedProviders,
      idTokenValidity: cdk.Duration.hours(1),
      accessTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
    });

    // Lambda@Edge — EdgeFunction은 자동으로 us-east-1에 배포
    this.edgeFunction = new cloudfront.experimental.EdgeFunction(this, 'EdgeAuth', {
      functionName: `${projectName}-edge-auth`,
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(lambdaSourceDir),
      memorySize: 128,
      timeout: cdk.Duration.seconds(5),
      logRetention: LOG_RETENTION,
    });

    // EdgeFunction은 자동으로 edgelambda.amazonaws.com trust를 추가함
  }
}
