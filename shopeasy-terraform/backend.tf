terraform {
  backend "s3" {
    bucket         = "shopeasy-tfstate-492660417055-v1"
    key            = "shopeasy/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "shopeasy-tfstate-lock"
    encrypt        = true
  }
}
