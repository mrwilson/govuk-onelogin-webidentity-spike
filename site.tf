locals {
  config = jsondecode(file("${path.module}/config.json"))
}

resource "aws_iam_openid_connect_provider" "identity_provider" {
  url             = local.config["one_login_url"]
  client_id_list  = [local.config["one_login_client_id"]]
  thumbprint_list = [local.config["one_login_ssl_thumbprint"]]
}

resource "aws_dynamodb_table" "webidentity-test-table" {
  name         = local.config["aws_dynamo_table"]
  hash_key     = "UserId"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "UserId"
    type = "S"
  }
}

resource "aws_iam_role" "web_identity_role" {
  name = "web_identity_test_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.identity_provider.arn
      }
      Condition = {
        StringEquals = {
          "${aws_iam_openid_connect_provider.identity_provider.url}:aud" : local.config["one_login_client_id"]
        }
      }
    }]
  })

  inline_policy {
    name = "DynamoAccess"
    policy = jsonencode({
      Version = "2012-10-17"

      Statement = [{
        Action   = ["dynamodb:PutItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.webidentity-test-table.arn
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:LeadingKeys" = "$${${aws_iam_openid_connect_provider.identity_provider.url}:sub}"
          }
      } }]
    })
  }
}

output "role_arn" {
  value = aws_iam_role.web_identity_role.arn
}