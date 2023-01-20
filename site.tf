locals {
  config = jsondecode(file("${path.module}/config.json"))
}

// The GOV.UK One Login OIDC-compliant identity provider
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
        // Only users who have authenticated with the federated
        // identity provider (GOV.UK One Login) can assume this role
        Federated = aws_iam_openid_connect_provider.identity_provider.arn
      }
      Condition = {
        StringEquals = {
          // Restrict the `aud` (audience) claim to the client id
          // corresponding to this specific Relying Party (RP)
          // to prevent ID tokens from other RPs being passed in
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
            // dynambodb:PutItem can only be executed against rows
            // with the "leading key" (hash key) equal to the `sub`
            // claim on the ID token used to generate these temporary
            // credentials with STS.
            //
            // Otherwise, the call fails with a permission denied error.
            "dynamodb:LeadingKeys" = "$${${aws_iam_openid_connect_provider.identity_provider.url}:sub}"
          }
      } }]
    })
  }
}

output "role_arn" {
  value = aws_iam_role.web_identity_role.arn
}