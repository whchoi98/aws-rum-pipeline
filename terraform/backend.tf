# terraform/backend.tf
terraform {
  backend "s3" {
    bucket         = "rum-pipeline-terraform-state"
    key            = "rum-pipeline/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
