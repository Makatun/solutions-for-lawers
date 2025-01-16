terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

resource "aws_iam_role" "visa_bulleting_grab_lambda_exec_role" {
  name = "visa_bulleting_grab_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "visa_bulleting_grab_lambda_policy" {
  role       = aws_iam_role.visa_bulleting_grab_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "visa_bulleting_grab_lambda" {
  function_name    = "visa_bulleting_grab_lambda"
  role             = aws_iam_role.visa_bulleting_grab_lambda_exec_role.arn
  handler          = "lambda_function.handler"
  runtime          = "nodejs18.x"
  filename         = "${path.module}/lambdas/visa_bulleting_grab_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambdas/visa_bulleting_grab_lambda.zip")
  timeout          = 10  // Timeout in seconds
  memory_size      = 200 // Memory size in MB
}

resource "aws_cloudwatch_event_rule" "every_1_minute" {
  name                = "every_1_minute"
  description         = "Fires every 1 minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "visa_bulleting_grab_lambda_target_1_minute" {
  rule      = aws_cloudwatch_event_rule.every_1_minute.name
  target_id = "visa_bulleting_grab_lambda_target_1_minute"
  arn       = aws_lambda_function.visa_bulleting_grab_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_1_minute" {
  statement_id  = "AllowExecutionFromCloudWatch_1_minute"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visa_bulleting_grab_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_1_minute.arn
}

resource "aws_s3_bucket" "visa_bulletin_s3" {
  bucket = "visa-bulleting-s3"

  tags = {
    Name        = "visa-bulleting-s3"
    Environment = "Dev"
  }
}

resource "aws_iam_role_policy" "visa_bulleting_grab_lambda_s3_policy" {
  name = "visa_bulleting_grab_lambda_s3_policy"
  role = aws_iam_role.visa_bulleting_grab_lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        Resource = [
          "arn:aws:s3:::visa-bulleting-s3",
          "arn:aws:s3:::visa-bulleting-s3/*"
        ]
      }
    ]
  })
}
