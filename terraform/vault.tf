# Vault Provider Configuration
resource "vault_mount" "database" {
  path = "database"
  type = "database"
}

# Database Secrets Engine Configuration
resource "vault_database_secret_backend_connection" "mysql" {
  backend       = vault_mount.database.path
  name          = "mysql"
  # Use the literal role name to avoid a dependency cycle: the role resource
  # references this connection (db_name), so referencing the role here
  # creates a circular dependency. Vault accepts role names as strings.
  allowed_roles = ["lambda-role"]

  mysql {
    connection_url = "{{username}}:{{password}}@tcp(${aws_db_instance.main.address}:3306)/"
    username       = var.database_master_username
    password       = random_password.rds_master_password.result
    max_open_connections = 10
    max_idle_connections = 5
    max_connection_lifetime = 14400 # 4 hours
  }
}

# Database Role for Lambda
resource "vault_database_secret_backend_role" "lambda" {
  backend             = vault_mount.database.path
  name                = "lambda-role"
  db_name             = vault_database_secret_backend_connection.mysql.name
  creation_statements = [
    "CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';",
    "GRANT SELECT, INSERT, UPDATE ON ${var.database_name}.* TO '{{name}}'@'%';"
  ]
  revocation_statements = [
    "DROP USER '{{name}}'@'%';"
  ]
  default_ttl = 3600  # 1 hour
  max_ttl     = 86400 # 24 hours
}

# Enable AWS Auth Method
resource "vault_auth_backend" "aws" {
  type = "aws"
}

# Configure AWS Auth Method
# Vault Policy for Lambda
resource "vault_policy" "lambda" {
  name = "lambda-policy"

  policy = <<EOT
path "database/creds/lambda-role" {
  capabilities = ["read"]
}
EOT
}

resource "vault_aws_auth_backend_role" "lambda" {
  backend                   = vault_auth_backend.aws.path
  role                      = "lambda-role"
  auth_type                 = "iam"
  bound_iam_principal_arns  = [aws_iam_role.lambda_exec.arn]
  token_policies            = [vault_policy.lambda.name]
  token_ttl                 = 3600
  token_max_ttl             = 86400
}