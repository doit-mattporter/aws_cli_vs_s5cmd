#!/usr/bin/env bash

# NOTE: This was run on a c7gn.16xlarge machine (200 Gbps throughput and 64 cores) with 12x 1126 GB gp3 EBS volumes in RAID0
# Each volume has 16,000 IOPS (max) and 1000 Mbps Throughput (max)
# These altogether help ensure that resources such as network throughput, disk throughput, and available processing power are minimal bottlenecks
# I ran this test using:
# s5cmd v2.2.2 released on Sept 15, 2023
# aws-cli/2.15.31 Python/3.11.8 released on March 20, 2024
# Linux/6.1.79-99.164.amzn2023.aarch64 exe/aarch64.amzn.2023

SOURCE_BUCKET=${1}
SAME_REGION_BUCKET=${2}
OTHER_REGION_BUCKET=${3}
AWS_CONFIGURATION=${4}

# Update the OS and packages
sudo dnf -y update > /dev/null 2>&1
sudo dnf upgrade -y 2>&1
sudo dnf install -y htop
sudo dnf -y autoremove > /dev/null 2>&1
os_latest_version=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')

# Function to clean up S3 folders
cleanup_s3() {
  local folder_name=$1
  s5cmd rm "s3://$SOURCE_BUCKET/${folder_name}/*" > /dev/null 2>&1
  s5cmd rm "s3://$SAME_REGION_BUCKET/${folder_name}/*" > /dev/null 2>&1
  s5cmd rm "s3://$OTHER_REGION_BUCKET/${folder_name}/*" > /dev/null 2>&1
}

# Clean up S3 and local folders from previous runs
rm -rf very_large_files* &
rm -rf large_files* &
rm -rf medium_files* &
rm -rf small_files* &
cleanup_s3 "very_large_files" &
cleanup_s3 "large_files" &
cleanup_s3 "medium_files" &
cleanup_s3 "small_files" &
wait

# Install s5cmd. This Go-based tool is compatible with S3 API calls and is much faster than 'aws s3 cp'
s5cmd_latest_version=$(curl -s https://api.github.com/repos/peak/s5cmd/releases/latest | jq -r '.tag_name')
filename_version=${s5cmd_latest_version#v}
mkdir s5cmd_download
wget -q -P s5cmd_download "https://github.com/peak/s5cmd/releases/download/${s5cmd_latest_version}/s5cmd_${filename_version}_Linux-arm64.tar.gz"
tar xf s5cmd_download/"s5cmd_${filename_version}_Linux-arm64.tar.gz" -C s5cmd_download
sudo mv s5cmd_download/s5cmd /usr/local/bin/
rm -rf s5cmd_download

# Update the AWS CLI
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
rm -f awscliv2.zip

# Helper functions
convert_time_to_seconds() {
    local time=$1
    local minutes=$(echo $time | awk -F'm' '{print $1}')
    local seconds=$(echo $time | awk -F'm' '{print $2}' | awk -F's' '{print $1}')
    echo $(echo "$minutes * 60 + $seconds" | bc)
}

convert_seconds_to_human_readable() {
    local total_seconds=$1
    local days=$(echo "$total_seconds / 86400" | bc)
    local hours=$(echo "($total_seconds - ($days * 86400)) / 3600" | bc)
    local minutes=$(echo "($total_seconds - ($days * 86400) - ($hours * 3600)) / 60" | bc)
    local seconds=$(echo "$total_seconds - ($days * 86400) - ($hours * 3600) - ($minutes * 60)" | bc)
    seconds=$(printf "%.2f" $seconds)
    echo "${days}d ${hours}h ${minutes}m ${seconds}s"
}

# Function to run bechmarking upload, download, and copy tests for specific file sizes adding up to 4 TB
run_tests() {
  local folder_name=$1
  local num_files=$2
  local file_size=$3
  local test_dir="/mnt/raid/${folder_name}"

  # Clean up previous runs
  rm -rf ${test_dir}*
  cleanup_s3 "${folder_name}"

  # Create the files to upload
  mkdir -p ${test_dir}/upload/
  seq 1 ${num_files} | xargs -I {} -P $(nproc) fallocate -l ${file_size} ${test_dir}/upload/${folder_name}_file_{}.bin

  # Perform the tests: upload, download, and copy between buckets
  echo -e "Running tests for $folder_name:\n" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
  test_upload_download_and_copy "${test_dir}"

  # Clean up
  rm -rf ${test_dir}*
  cleanup_s3 "${folder_name}"
}

test_upload_download_and_copy() {
  local test_dir=$1
  local folder_name=$(basename "$test_dir")

  # Upload to S3 and time with s5cmd
  s5cmd_upload_time=$( { time s5cmd cp "${test_dir}/upload/*" s3://$SOURCE_BUCKET/${folder_name}/s5cmd/ > /dev/null; } 2>&1 )
  s5cmd_upload_seconds=$(convert_time_to_seconds $(echo "$s5cmd_upload_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' upload from EC2 to same-region bucket: $(convert_seconds_to_human_readable $s5cmd_upload_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Download to EC2 from S3 and time with s5cmd
  mkdir -p "${test_dir}/s5cmd/download/"
  s5cmd_download_time=$( { time s5cmd cp s3://$SOURCE_BUCKET/${folder_name}/s5cmd/* "${test_dir}/s5cmd/download/" > /dev/null; } 2>&1 )
  s5cmd_download_seconds=$(convert_time_to_seconds $(echo "$s5cmd_download_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' download from same-region bucket to EC2: $(convert_seconds_to_human_readable $s5cmd_download_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Copy to same-region bucket and time with s5cmd
  s5cmd_same_region_copy_time=$( { time s5cmd cp "s3://$SOURCE_BUCKET/${folder_name}/s5cmd/*" s3://$SAME_REGION_BUCKET/${folder_name}/s5cmd/ > /dev/null; } 2>&1 )
  s5cmd_same_region_copy_seconds=$(convert_time_to_seconds $(echo "$s5cmd_same_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' same-region bucket to same-region bucket copy: $(convert_seconds_to_human_readable $s5cmd_same_region_copy_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Copy to other-region bucket and time with s5cmd
  s5cmd_other_region_copy_time=$( { time s5cmd cp "s3://$SAME_REGION_BUCKET/${folder_name}/s5cmd/*" s3://$OTHER_REGION_BUCKET/${folder_name}/s5cmd/ > /dev/null; } 2>&1 )
  s5cmd_other_region_copy_seconds=$(convert_time_to_seconds $(echo "$s5cmd_other_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' same-region bucket to other-region bucket copy: $(convert_seconds_to_human_readable $s5cmd_other_region_copy_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Upload to S3 and time with aws s3 cp
  aws_upload_time=$( { time aws s3 cp ${test_dir}/upload/ s3://$SOURCE_BUCKET/${folder_name}/awscli/ --recursive --quiet; } 2>&1 )
  aws_upload_seconds=$(convert_time_to_seconds $(echo "$aws_upload_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' upload from EC2 to same-region bucket: $(convert_seconds_to_human_readable $aws_upload_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Download to EC2 from S3 and time with aws s3 cp
  mkdir -p "${test_dir}/awscli/download/"
  aws_download_time=$( { time aws s3 cp s3://$SOURCE_BUCKET/${folder_name}/awscli/ ${test_dir}/awscli/download/ --recursive --quiet; } 2>&1 )
  aws_download_seconds=$(convert_time_to_seconds $(echo "$aws_download_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' download from same-region bucket to EC2: $(convert_seconds_to_human_readable $aws_download_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Copy to same-region bucket and time with aws s3 cp
  aws_same_region_copy_time=$( { time aws s3 cp s3://$SOURCE_BUCKET/${folder_name}/awscli/ s3://$SAME_REGION_BUCKET/${folder_name}/awscli/ --recursive --quiet; } 2>&1 )
  aws_same_region_copy_seconds=$(convert_time_to_seconds $(echo "$aws_same_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' same-region bucket to same-region bucket copy: $(convert_seconds_to_human_readable $aws_same_region_copy_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Copy to other-region bucket and time with aws s3 cp
  aws_other_region_copy_time=$( { time aws s3 cp s3://$SAME_REGION_BUCKET/${folder_name}/awscli/ s3://$OTHER_REGION_BUCKET/${folder_name}/awscli/ --recursive --quiet; } 2>&1 )
  aws_other_region_copy_seconds=$(convert_time_to_seconds $(echo "$aws_other_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' same-region bucket to other-region bucket copy: $(convert_seconds_to_human_readable $aws_other_region_copy_seconds)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  # Calculate and display time differences and percentage differences
  upload_time_diff=$(echo "$aws_upload_seconds - $s5cmd_upload_seconds" | bc)
  upload_fold_improvement=$(echo "scale=2; $aws_upload_seconds / $s5cmd_upload_seconds" | bc)
  echo "Upload time difference (aws s3 cp vs s5cmd): aws s3 cp is ${upload_time_diff} seconds slower (~${upload_fold_improvement}X slower than s5cmd)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  download_time_diff=$(echo "$aws_download_seconds - $s5cmd_download_seconds" | bc)
  download_fold_improvement=$(echo "scale=2; $aws_download_seconds / $s5cmd_download_seconds" | bc)
  echo "Download time difference (aws s3 cp vs s5cmd): aws s3 cp is ${download_time_diff} seconds slower (~${download_fold_improvement}X slower than s5cmd)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  same_region_copy_time_diff=$(echo "$aws_same_region_copy_seconds - $s5cmd_same_region_copy_seconds" | bc)
  same_region_copy_fold_improvement=$(echo "scale=2; $aws_same_region_copy_seconds / $s5cmd_same_region_copy_seconds" | bc)
  echo "Same-region bucket-to-bucket copy time difference (aws s3 cp vs s5cmd): aws s3 cp is ${same_region_copy_time_diff} seconds slower (~${same_region_copy_fold_improvement}X slower than s5cmd)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

  other_region_copy_time_diff=$(echo "$aws_other_region_copy_seconds - $s5cmd_other_region_copy_seconds" | bc)
  other_region_copy_fold_improvement=$(echo "scale=2; $aws_other_region_copy_seconds / $s5cmd_other_region_copy_seconds" | bc)
  echo "Same-to-other-region bucket-to-bucket copy time difference (aws s3 cp vs s5cmd): aws s3 cp is ${other_region_copy_time_diff} seconds slower (~${other_region_copy_fold_improvement}X slower than s5cmd)" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
}

# Configure 12x EBS volumes to be in RAID0 configuration with an ext4 filesystem
sudo yum install -y mdadm
DEVICES=()
for i in {1..12}; do
    DEVICES+=("/dev/nvme${i}n1")
done

# Function to check if a device is available
check_device() {
    if [ -b "$1" ]; then
        echo "Device $1 is available."
        return 0
    else
        echo "Waiting for device $1..."
        return 1
    fi
}

# Loop through each device and wait until it's available
for DEVICE in "${DEVICES[@]}"; do
    while ! check_device "$DEVICE"; do
        sleep 5
    done
done

# Now that all devices are available, proceed with RAID0 setup
sudo mdadm --create --verbose /dev/md0 --level=0 --name=MY_RAID --raid-devices=12 "${DEVICES[@]}"
sudo mkfs.ext4 -L MY_RAID /dev/md0
sudo mkdir -p /mnt/raid
sudo mount /dev/md0 /mnt/raid
# Ensure the RAID array is mounted automatically at boot
echo "/dev/md0 /mnt/raid ext4 defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab

# Test scenarios for Large, Medium, and Small files adding up to 4 TB
# Very large files: 5 GBs each
# Large files: 1 GB each
# Medium files: 32 MBs each
# Small files: 256 KBs each

# Report on OS and tool versions
{
  echo "OS version:"
  echo "${os_latest_version}"
  echo ""
  echo "s5cmd version:"
  s5cmd version
  echo ""
  echo "AWS CLI version:"
  aws --version
  echo ""
  echo "AWS CLI s3 Configuration (Defaults shown if not configured):"
  echo "max_concurrency: $(aws configure get default.s3.max_concurrency || echo 'Determined dynamically, typically 10')"
  echo "multipart_threshold: $(aws configure get default.s3.multipart_threshold || echo '8MB')"
  echo "multipart_chunksize: $(aws configure get default.s3.multipart_chunksize || echo '8MB')"
  echo ""
} > /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

echo "Starting benchmark tests for S3 file operations..." >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
echo "" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

# Very Large files test
echo "=== Very Large Files Test ===" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
run_tests "very_large_files" 819 "5G"
echo "" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

# Large files test
echo "=== Large Files Test ===" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
run_tests "large_files" 4096 "1G"
echo "" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

# Medium files test
echo "=== Medium Files Test ===" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
run_tests "medium_files" 131072 "32M"
echo "" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

# Small files test
echo "=== Small Files Test ===" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt
run_tests "small_files" 16777216 "256K"
echo "" >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

echo "All tests completed." >> /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt

s5cmd cp /mnt/raid/benchmarks_${AWS_CONFIGURATION}.txt s3://${SOURCE_BUCKET}/benchmarks_${AWS_CONFIGURATION}.txt
