# govuk-onelogin-webidentity-spike

Proof of concept for using `AssumeRoleWithWebIdentity` in `AWS` using `GOV.UK OneLogin` as an identity provider.

## Running

1. Set up a Relying Party (RP) in GOV.UK One Login, using private_key_jwt and `IdTokenSigningAlgorithm` set to `RS256` (AWS does not support `ES256` at this time).
2. Create `config.json` from `config.json.template`, filling out all variables apart from `aws_role_to_assume` (this is generated by the Terraform)
3. Run Terraform against an AWS account of your choice
4. Add the role arn to `config.json`

```
$ npm install
$ node -e 'require("./app").run()'
```