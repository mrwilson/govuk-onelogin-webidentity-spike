// Express dependencies for creating a Relying Party
const express = require("express");
const app = express();
const { auth } = require("express-openid-connect");

// AWS imports and initialising an STS client
const { DynamoDB } = require("@aws-sdk/client-dynamodb");
const { STS } = require("@aws-sdk/client-sts");
const stsClient = new STS({ region: "eu-west-2" });

// Utility imports
const crypto = require("crypto");
const jose = require("jose");
const fs = require("fs");

// Loading config from JSON file
const config = JSON.parse(fs.readFileSync("config.json", "utf8"));

function content(response) {
  return `<html lang="en">
        <head>
            <title>Demo Page</title>
        </head>
        <body>
            <p>Hello, your favourite food is ${response.Item.FavouriteFood.S}!</p>
        </body>
    </html>`;
}

module.exports.run = async function () {
  const privatekey = await jose.importPKCS8(
    fs.readFileSync(config["one_login_signing_private_key"]).toString(),
    "RS256"
  );

  var jwk = await jose.exportJWK(privatekey);

  app.use(
    // Use GOV.UK One Login to secure urls on this web service
    auth({
      issuerBaseURL: config["one_login_url"],
      baseURL: "http://localhost:3031/",
      clientID: config["one_login_client_id"],
      secret: crypto.randomBytes(20).toString("base64url"),
      clientAuthMethod: "private_key_jwt",
      clientAssertionSigningKey: jwk,
      idTokenSigningAlg: "RS256",
      authRequired: true,
      authorizationParams: {
        response_type: "code",
        scope: "openid email phone",
      },
    })
  );

  app.get("/", async (req, res) => {
    // Pass the GOV.UK One Login ID token to AWS STS
    // to get a set of temporary credentials
    const assumedRole = await stsClient.assumeRoleWithWebIdentity({
      RoleSessionName: "ExampleSessionName",
      RoleArn: config["aws_role_to_assume"],
      WebIdentityToken: req.oidc.idToken,
    });

    // Dynamo access using the temporary credentials
    // from the ID token
    const dynamo = new DynamoDB({
      region: "eu-west-2",
      credentials: {
        accessKeyId: assumedRole.Credentials.AccessKeyId,
        secretAccessKey: assumedRole.Credentials.SecretAccessKey,
        sessionToken: assumedRole.Credentials.SessionToken,
      },
    });

    // The assumed role only allows access
    // to rows where the leading key (partition key)
    // is equal to the sub of the ID.
    //
    // This role is set up in the neighbouring Terraform file.
    dynamo
      .getItem({
        TableName: config["aws_dynamo_table"],
        Item: {
          UserId: { S: jose.decodeJwt(req.oidc.idToken).sub },
        },
      })
      .then((response) => res.send(content(response)))
      .catch((error) => res.send(error.message));
  });

  app.listen(3031);
};
