provider "aws" {
  region = var.region
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

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

resource "aws_codepipeline" "build_pipeline" {
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
}
/*
resource "aws_codebuild_project" "eks_deployment_project" {
  name          = "eks-deployment-project"
  service_role  = aws_iam_role.eks_deployment_role.arn
  build_timeout = "5"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type = "CODEPIPELINE"
  }

  depends_on = [aws_iam_role_policy_attachment.attach_eks_deployment_policy]
}

resource "aws_codepipeline" "deploy_pipeline" {
  name          = "deploy-${var.code_pipeline_name}"
  role_arn      = aws_iam_role.code_pipeline_role.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.code_pipeline_artifacts_bucket.id
    type     = "S3"
  }

  stage {
    name = "BuildAndDeploy"

    action {
      name             = "BuildAndDeploy"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.eks_deployment_project.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToEKS"
      category        = [aws_iam_role.code_deploy_role.arn]
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.eks_deployment_project.name
      }
    }
  }  
}
*/

