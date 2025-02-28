# S3 bucket for storing files
resource "aws_s3_bucket" "file_storage" {
  bucket = "visa-bulleting-s3"
  # bucket_prefix = "file-api-storage-" # Using prefix for unique name generation
}

# S3 bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "file_storage_policy" {
  bucket = aws_s3_bucket.file_storage.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.api_gateway_s3_role.arn
        }
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.file_storage.arn}/*"
      }
    ]
  })
}

# S3 bucket ACL
resource "aws_s3_bucket_acl" "file_storage" {
  depends_on = [aws_s3_bucket_ownership_controls.file_storage]
  bucket     = aws_s3_bucket.file_storage.id
  acl        = "private"
}

# S3 bucket CORS configuration
resource "aws_s3_bucket_cors_configuration" "file_storage" {
  bucket = aws_s3_bucket.file_storage.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "Content-Type", "Content-Length"]
    max_age_seconds = 3000
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "s3_api" {
  name        = "s3-file-api"
  description = "API to serve files from S3"

  binary_media_types = ["*/*"] # Allow all binary media types

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Files resource
resource "aws_api_gateway_resource" "files" {
  rest_api_id = aws_api_gateway_rest_api.s3_api.id
  parent_id   = aws_api_gateway_rest_api.s3_api.root_resource_id
  path_part   = "files"
}

# Files resource with path parameter
resource "aws_api_gateway_resource" "file_path" {
  rest_api_id = aws_api_gateway_rest_api.s3_api.id
  parent_id   = aws_api_gateway_resource.files.id
  path_part   = "{file_path+}"
}

# IAM role for API Gateway to access S3
resource "aws_iam_role" "api_gateway_s3_role" {
  name = "api_gateway_s3_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for API Gateway to access S3
resource "aws_iam_policy" "api_gateway_s3_policy" {
  name        = "api_gateway_s3_policy"
  description = "Allow API Gateway to access S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.file_storage.arn}/*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "api_gateway_s3_policy_attachment" {
  role       = aws_iam_role.api_gateway_s3_role.name
  policy_arn = aws_iam_policy.api_gateway_s3_policy.arn
}

# Method for file_path resource - requiring API key
resource "aws_api_gateway_method" "file_path_method" {
  rest_api_id      = aws_api_gateway_rest_api.s3_api.id
  resource_id      = aws_api_gateway_resource.file_path.id
  http_method      = "GET"
  authorization    = "NONE" # Corrected from authorization_type
  api_key_required = true   # Require API key

  request_parameters = {
    "method.request.path.file_path" = true
  }
}

# Integration with S3 for file_path resource
resource "aws_api_gateway_integration" "file_path_integration" {
  rest_api_id             = aws_api_gateway_rest_api.s3_api.id
  resource_id             = aws_api_gateway_resource.file_path.id
  http_method             = aws_api_gateway_method.file_path_method.http_method
  integration_http_method = "GET"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:us-east-1:s3:path/${aws_s3_bucket.file_storage.id}/{key}"
  credentials             = aws_iam_role.api_gateway_s3_role.arn

  request_parameters = {
    "integration.request.path.key" = "method.request.path.file_path"
  }
}

# Method response for file_path resource
resource "aws_api_gateway_method_response" "file_path_method_response" {
  rest_api_id = aws_api_gateway_rest_api.s3_api.id
  resource_id = aws_api_gateway_resource.file_path.id
  http_method = aws_api_gateway_method.file_path_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Type"                = true
    "method.response.header.Content-Length"              = true
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration response for file_path resource
resource "aws_api_gateway_integration_response" "file_path_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.s3_api.id
  resource_id = aws_api_gateway_resource.file_path.id
  http_method = aws_api_gateway_method.file_path_method.http_method
  status_code = aws_api_gateway_method_response.file_path_method_response.status_code

  response_parameters = {
    "method.response.header.Content-Type"                = "integration.response.header.Content-Type"
    "method.response.header.Content-Length"              = "integration.response.header.Content-Length"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "s3_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.file_path_integration,
    aws_api_gateway_integration_response.file_path_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_api.id

  # Using a timestamp to force redeployment when changes are made
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.file_path.id,
      aws_api_gateway_method.file_path_method.id,
      aws_api_gateway_integration.file_path_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "s3_api_stage" {
  deployment_id = aws_api_gateway_deployment.s3_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.s3_api.id
  stage_name    = var.stage_name
}

# Create an API key
resource "aws_api_gateway_api_key" "file_api_key" {
  name        = "file-api-key"
  description = "API key for accessing S3 files"
  enabled     = true
}

# Create a usage plan
resource "aws_api_gateway_usage_plan" "file_api_usage_plan" {
  name        = "file-api-usage-plan"
  description = "Usage plan for S3 file API"

  api_stages {
    api_id = aws_api_gateway_rest_api.s3_api.id
    stage  = aws_api_gateway_stage.s3_api_stage.stage_name
  }

  quota_settings {
    limit  = 10000 # Total requests allowed per month
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 20 # Max concurrent requests
    rate_limit  = 10 # Requests per second
  }
}

# Associate API key with usage plan
resource "aws_api_gateway_usage_plan_key" "file_api_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.file_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.file_api_usage_plan.id
}

# Outputs
output "api_endpoint" {
  value       = "${aws_api_gateway_stage.s3_api_stage.invoke_url}/files/"
  description = "The API endpoint for accessing files"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.file_storage.id
  description = "The name of the S3 bucket storing the files"
}

output "api_key" {
  value       = aws_api_gateway_api_key.file_api_key.value
  sensitive   = true # Mark as sensitive to avoid showing in logs
  description = "API key for accessing the file API"
}
