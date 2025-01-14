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
  region = "us-east-1"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

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

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "my_lambda" {
  function_name    = "my_lambda"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.handler"
  runtime          = "nodejs18.x"
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  timeout          = 10 // Timeout in seconds
}

resource "aws_cloudwatch_event_rule" "every_1_minute" {
  name                = "every_1_minute"
  description         = "Fires every 1 minute"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_target_1_minute" {
  rule      = aws_cloudwatch_event_rule.every_1_minute.name
  target_id = "lambda_target_1_minute"
  arn       = aws_lambda_function.my_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_1_minute" {
  statement_id  = "AllowExecutionFromCloudWatch_1_minute"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_1_minute.arn
}
