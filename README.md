# terraform-containerized-app-poc

This code is being run under `terraform apply` command. Terraform should build the Docker image locally, get authenticated to freshly created ECR repository, push the image as `latest` one and spin it up on the new ECS cluster as a Fargate service.

The expected result is the application running under techtaskchallenge.api.com domain accessible by 2 routes: `/` and `/hello`.

## Requirements

You need to have following programs installed in your $PATH:

* bash
* md5sum or md5
* aws
* docker
* terraform >= 0.14

