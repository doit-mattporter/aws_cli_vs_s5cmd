# aws_cli_vs_s5cmd
## Compare data transfer performance for the AWS CLI vs. s5cmd

In order to reproduce the benchmarks mentioned in the Medium blog post [Save Time and Money on S3 Data Transfers: Surpass AWS CLI Performance by Up to 80X](https://engineering.doit.com/save-time-and-money-on-s3-data-transfers-surpass-aws-cli-performance-by-up-to-80x), follow the steps below:

1. Install [Terraform](https://www.terraform.io/) and the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. Navigate to `terraform/` and run `terraform init`
3. Update the `variables.tf` file so that each variable has a sensible default value. Most variables can probably be left at their existing defaults - you are only required to provide:
    1. `key_name`: An EC2 key pair name that exists in the region you'll be running benchmarking within
    2. `vpc_id`: The VPC ID for the region you'll be running benchmarking within
4. To help ensure cloud account safety: Configure your AWS CLI so that it is authenticated with an empty playground AWS account
5. Run `terraform apply`
6. Wait about 5 weeks. You will eventually see `benchmarks_default_aws_config.txt` and `benchmarks_optimized_aws_config.txt` uploaded to an S3 bucket named `benchmark-same-region-bucket-<RANDOM_STRING>`. These files will contain the benchmarking results for all scenarios covered in the blog.
    * Should you want to observe benchmarking progress live, SSH into the EC2 instance spun up by your Terraform apply command and run `clear && cat /mnt/raid/benchmarks*.txt`
    * Should you want to speed up the benchmarking process, prior to running `terraform apply`, update `startup_benchmarking_script.sh` for all instances where `run_tests` is invoked such that fewer than 4 TBs of files are created for benchmarking. For example, you could reduce the amount of data that has to be uploaded/downloaded/copied during benchmarking by 4X by changing `run_tests "large_files" 4096 "1G"` to `run_tests "large_files" 1024 "1G"`, as this reduces the quantity of 1 GB files created by 4X. AWS CLI commands are a huge bottleneck; decreasing the total quantity of data that `aws s3 cp` commands have to run is the primary way to reduce overall benchmarking runtime.
