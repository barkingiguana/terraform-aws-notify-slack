provider "aws" {
  alias   = "notifier"
  version = "~> 1.27"

  assume_role {
    role_arn = "${var.role_arn}"
  }

  region = "${var.region}"
}

data "aws_sns_topic" "this" {
  provider = "aws.notifier"
  count = "${(1 - var.create_sns_topic) * var.create}"

  kms_master_key_id = "${var.sns_topic_kms_key_id}"
  name = "${var.sns_topic_name}"
}

resource "aws_sns_topic" "this" {
  provider = "aws.notifier"
  count = "${var.create_sns_topic * var.create}"

  name = "${var.sns_topic_name}"
}

locals {
  lambda_default_path = "${substr("${path.module}/functions/notify_slack.py", length(path.cwd) + 1, -1)}"
  sns_topic_arn = "${element(compact(concat(aws_sns_topic.this.*.arn, data.aws_sns_topic.this.*.arn, list(""))), 0)}"
  lambda_path = "${var.lambda_path == "NONE" ? local.lambda_default_path : var.lambda_path}"
}

resource "aws_sns_topic_subscription" "sns_notify_slack" {
  provider = "aws.notifier"
  count = "${var.create}"

  topic_arn = "${local.sns_topic_arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.notify_slack.0.arn}"
}

resource "aws_lambda_permission" "sns_notify_slack" {
  provider = "aws.notifier"
  count = "${var.create}"

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.notify_slack.0.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${local.sns_topic_arn}"
}

data "null_data_source" "lambda_file" {
  inputs {
    filename = "${local.lambda_path}"
  }
}

data "null_data_source" "lambda_archive" {
  inputs {
    filename = "${substr("${path.module}/functions/notify_slack.zip", length(path.cwd) + 1, -1)}"
  }
}

data "archive_file" "notify_slack" {
  count = "${var.create}"

  type        = "zip"
  source_file = "${data.null_data_source.lambda_file.outputs.filename}"
  output_path = "${data.null_data_source.lambda_archive.outputs.filename}"
}

resource "aws_lambda_function" "notify_slack" {
  provider = "aws.notifier"
  count = "${var.create}"

  filename = "${data.archive_file.notify_slack.0.output_path}"

  function_name = "${var.lambda_function_name}"

  role             = "${aws_iam_role.lambda.arn}"
  handler          = "notify_slack.lambda_handler"
  source_code_hash = "${data.archive_file.notify_slack.0.output_base64sha256}"
  runtime          = "python3.6"
  timeout          = 30
  kms_key_arn      = "${var.kms_key_arn}"

  environment {
    variables = {
      SLACK_WEBHOOK_URL = "${var.slack_webhook_url}"
      SLACK_CHANNEL     = "${var.slack_channel}"
      SLACK_USERNAME    = "${var.slack_username}"
      SLACK_EMOJI       = "${var.slack_emoji}"
    }
  }

  lifecycle {
    ignore_changes = [
      "filename",
      "last_modified",
    ]
  }
}
