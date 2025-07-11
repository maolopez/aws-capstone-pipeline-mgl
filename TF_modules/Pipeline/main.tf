provider "aws" {
  region = var.region
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "code_build_role" {
  name = "CBRole-${var.code_build_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "code_build_default_policy" {
  name = "CBDefaultPolicy-${var.code_build_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.code_build_name}*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["codebuild:BatchPutCodeCoverages", "codebuild:BatchPutTestCases", "codebuild:CreateReport", "codebuild:CreateReportGroup", "codebuild:UpdateReport"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:codebuild:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:report-group/${var.code_build_name}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetBucket*", "s3:GetObject*", "s3:List*", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.code_pipeline_artifacts_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["codestar-connections:*"]
        Resource = [
          aws_codestarconnections_connection.codestarconn.arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
        Resource = [
          "*"
        ]
      }      
    ]
  })
 
}

resource "aws_iam_role_policy_attachment" "attach_codebuild_policy" {
  policy_arn = aws_iam_policy.code_build_default_policy.arn
  role       = aws_iam_role.code_build_role.name
}

resource "aws_codestarconnections_connection" "codestarconn" {
  name          = var.codestarconnection
  provider_type = "GitHub"
}

resource "aws_codebuild_project" "code_build_project" {
  name         = var.code_build_name
  description  = "Build python source code"
  service_role = aws_iam_role.code_build_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.full_repository_id}.git"
    #buildspec = "buildspec.yml" only for type NO SOURCE
    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codestarconnections_connection.codestarconn.arn
    }
  }

  cache {
    type = "NO_CACHE"
  }
  encryption_key = "alias/aws/s3"

  depends_on = [
    aws_iam_role_policy_attachment.attach_codebuild_policy,
    aws_codestarconnections_connection.codestarconn
  ]
}

resource "aws_s3_bucket" "code_pipeline_artifacts_bucket" {
  bucket = "${var.code_pipeline_name}-bucket"

}

resource "aws_s3_bucket_public_access_block" "code_pipeline_artifacts_bucket_policy" {
  bucket = aws_s3_bucket.code_pipeline_artifacts_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "code_pipeline_role" {
  name = "CPRole-${var.code_pipeline_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "code_pipeline_default_policy" {
  name = "CPDefaultPolicy-${var.code_pipeline_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["${aws_s3_bucket.code_pipeline_artifacts_bucket.arn}/*"]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codepipeline/${var.code_pipeline_name}*"]
      },
      {
        Effect   = "Allow"
        Action   = ["inspector-scan:ScanSbom"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["codestar-connections:*"]
        Resource = [
          aws_codestarconnections_connection.codestarconn.arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["codebuild:*"]
        Resource = [
          "arn:aws:codebuild:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:project/*"
        ]
      }           
    ]
  })
}

resource "aws_iam_policy" "github_ecr_policy" {
  name   = "GithubEcrPolicy-${var.code_pipeline_name}"
  policy = file("../TF_modules/Pipeline/github-ecr-interact.json")
}

resource "aws_iam_role_policy_attachment" "attach_codepipeline_policy" {
  policy_arn = aws_iam_policy.code_pipeline_default_policy.arn
  role       = aws_iam_role.code_pipeline_role.name
}

resource "aws_iam_role_policy_attachment" "attach_github_ecr_policy" {
  policy_arn = aws_iam_policy.github_ecr_policy.arn
  role       = aws_iam_role.code_pipeline_role.name
}

resource "aws_codepipeline" "pipeline" {
  name          = var.code_pipeline_name
  role_arn      = aws_iam_role.code_pipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.code_pipeline_artifacts_bucket.id
    type     = "S3"
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "CodeConnections"
      push {
        branches {
          includes = [var.branch_name]
        }
      }
    }
  }

  stage {
    name = "Source"

    action {
      name             = "CodeConnections"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.codestarconn.arn
        FullRepositoryId = var.full_repository_id
        BranchName       = var.branch_name
        DetectChanges    = true
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.code_build_project.name
      }
    }
  }
/*
    stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "EKS"
      input_artifacts = ["SourceOutput"]
      version         = "1"

      configuration = {
        ClusterName = var.eksclustername
        ManifestFiles = "deploy_serve.yaml"
      }
    }
  }



  depends_on = [
    aws_iam_role_policy_attachment.attach_codepipeline_policy,
    aws_iam_role_policy_attachment.attach_github_ecr_policy
  ]
*/
}
