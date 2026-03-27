terraform {
  backend "s3" {
    bucket         = "umar-tfstate-dev-1"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "dynamo-demo"
  }
}
