#!/usr/bin/env bash

# Set your source + target (same-region) bucket, and target (other-region) bucket
SOURCE_BUCKET=${1}
SAME_REGION_BUCKET=${2}
OTHER_REGION_BUCKET=${3}

# Update the OS and packages
sudo dnf -y update > /dev/null 2>&1
output=$(sudo dnf upgrade -y 2>&1)
sudo dnf -y autoremove > /dev/null 2>&1
os_latest_version=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')


# NOTE: This was run on a c7gn.16xlarge machine (200 Gbps throughput and 64 cores) with an 4x 1024 GB gp3 EBS volumes in RAID0
# Each volume has 16,000 IOPS (max) and 1000 Mbps Throughput (max)
# These altogether help ensure that resources such as VM network throughput, EBS volume throughput, and CPU cores are minimal bottlenecks.
# I ran this test using:
# s5cmd v2.2.2 released on Sept 15, 2023
# aws-cli/2.15.31 Python/3.11.8 released on March 20, 2024
# Linux/6.1.79-99.164.amzn2023.aarch64 exe/aarch64.amzn.2023

# Function to clean up S3 folders
cleanup_s3() {
  local folder_name=$1
  s5cmd rm "s3://$SOURCE_BUCKET/${folder_name}/*" > /dev/null 2>&1
  s5cmd rm "s3://$SAME_REGION_BUCKET/${folder_name}/*" > /dev/null 2>&1
  s5cmd rm "s3://$OTHER_REGION_BUCKET/${folder_name}/*" > /dev/null 2>&1
}

# Clean up S3 and local folders from previous runs
rm -rf large_files* &
rm -rf medium_files* &
rm -rf small_files* &
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
    echo "${days}d ${hours}h ${minutes}m ${seconds}s"
}

# Function to run bechmarking upload & copy tests for specific file sizes adding up to 4 TB
run_tests() {
  local folder_name=$1
  local num_files=$2
  local file_size=$3
  # Ensure the folder is within the RAID0 mount
  local test_dir="/mnt/raid/${folder_name}"

  # Clean up previous runs
  rm -rf ${test_dir}*
  cleanup_s3 "${folder_name}"

  # Create a folder and files for the test
  mkdir -p ${test_dir}
  seq 1 ${num_files} | xargs -I {} -P $(nproc) fallocate -l ${file_size} ${test_dir}/${folder_name}_file_{}.bin

  echo -e "Running tests for $folder_name:\n" >> /mnt/raid/benchmarks.txt

  # Perform the tests: upload, copy, and then clean up
  test_upload_and_copy "${test_dir}"

  # Clean up after tests
  rm -rf ${test_dir}*
  cleanup_s3 "${folder_name}"
}

test_upload_and_copy() {
  local test_dir=$1
  local folder_name=$(basename "$test_dir")

  # Upload to S3 and time with s5cmd
  s5cmd_upload_time=$( { time s5cmd cp "${test_dir}/*" s3://$SOURCE_BUCKET/${folder_name}/s5cmd/ > /dev/null; } 2>&1 )
  s5cmd_upload_seconds=$(convert_time_to_seconds $(echo "$s5cmd_upload_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' upload from EC2 to same-region bucket: $(convert_seconds_to_human_readable $s5cmd_upload_seconds)" >> /mnt/raid/benchmarks.txt

  # Copy to same-region bucket and time with s5cmd
  s5cmd_same_region_copy_time=$( { time s5cmd cp "s3://$SOURCE_BUCKET/${folder_name}/s5cmd/*" s3://$SAME_REGION_BUCKET/${folder_name}/s5cmd/ > /dev/null; } 2>&1 )
  s5cmd_same_region_copy_seconds=$(convert_time_to_seconds $(echo "$s5cmd_same_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' same-region bucket to same-region bucket copy: $(convert_seconds_to_human_readable $s5cmd_same_region_copy_seconds)" >> /mnt/raid/benchmarks.txt

  # Copy to other-region bucket and time with s5cmd
  s5cmd_other_region_copy_time=$( { time s5cmd cp "s3://$SAME_REGION_BUCKET/${folder_name}/s5cmd/*" s3://$OTHER_REGION_BUCKET/${folder_name}/s5cmd/ > /dev/null; } 2>&1 )
  s5cmd_other_region_copy_seconds=$(convert_time_to_seconds $(echo "$s5cmd_other_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 's5cmd cp' same-region bucket to other-region bucket copy: $(convert_seconds_to_human_readable $s5cmd_other_region_copy_seconds)" >> /mnt/raid/benchmarks.txt

  # Upload to S3 and time with aws s3 cp
  aws_upload_time=$( { time aws s3 cp ${test_dir} s3://$SOURCE_BUCKET/${folder_name}/awscli/ --recursive --quiet; } 2>&1 )
  aws_upload_seconds=$(convert_time_to_seconds $(echo "$aws_upload_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' upload from EC2 to same-region bucket: $(convert_seconds_to_human_readable $aws_upload_seconds)" >> /mnt/raid/benchmarks.txt

  # Copy to same-region bucket and time with aws s3 cp
  aws_same_region_copy_time=$( { time aws s3 cp s3://$SOURCE_BUCKET/${folder_name}/awscli/ s3://$SAME_REGION_BUCKET/${folder_name}/awscli/ --recursive --quiet; } 2>&1 )
  aws_same_region_copy_seconds=$(convert_time_to_seconds $(echo "$aws_same_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' same-region bucket to same-region bucket copy: $(convert_seconds_to_human_readable $aws_same_region_copy_seconds)" >> /mnt/raid/benchmarks.txt

  # Copy to other-region bucket and time with aws s3 cp
  aws_other_region_copy_time=$( { time aws s3 cp s3://$SAME_REGION_BUCKET/${folder_name}/awscli/ s3://$OTHER_REGION_BUCKET/${folder_name}/awscli/ --recursive --quiet; } 2>&1 )
  aws_other_region_copy_seconds=$(convert_time_to_seconds $(echo "$aws_other_region_copy_time" | grep real | awk '{print $2}'))
  echo "Runtime for 'aws s3 cp' same-region bucket to other-region bucket copy: $(convert_seconds_to_human_readable $aws_other_region_copy_seconds)" >> /mnt/raid/benchmarks.txt

  # Calculate and display time differences and percentage differences
  upload_time_diff=$(echo "$aws_upload_seconds - $s5cmd_upload_seconds" | bc)
  upload_percent_diff=$(echo "scale=2; ($aws_upload_seconds - $s5cmd_upload_seconds) / $aws_upload_seconds * 100" | bc)
  echo "Upload time difference (aws s3 cp vs s5cmd): aws s3 cp is ${upload_time_diff} seconds (${upload_percent_diff}%) slower" >> /mnt/raid/benchmarks.txt

  same_region_copy_time_diff=$(echo "$aws_same_region_copy_seconds - $s5cmd_same_region_copy_seconds" | bc)
  same_region_copy_percent_diff=$(echo "scale=2; ($aws_same_region_copy_seconds - $s5cmd_same_region_copy_seconds) / $aws_same_region_copy_seconds * 100" | bc)
  echo "Same-region bucket-to-bucket copy time difference (aws s3 cp vs s5cmd): aws s3 cp is ${same_region_copy_time_diff} seconds (${same_region_copy_percent_diff}%) slower" >> /mnt/raid/benchmarks.txt

  other_region_copy_time_diff=$(echo "$aws_other_region_copy_seconds - $s5cmd_other_region_copy_seconds" | bc)
  other_region_copy_percent_diff=$(echo "scale=2; ($aws_other_region_copy_seconds - $s5cmd_other_region_copy_seconds) / $aws_other_region_copy_seconds * 100" | bc)
  echo "Same-to-Other-region bucket-to-bucket copy time difference (aws s3 cp vs s5cmd): aws s3 cp is ${other_region_copy_time_diff} seconds (${other_region_copy_percent_diff}%) slower" >> /mnt/raid/benchmarks.txt
}

# Configure 4x EBS volumes to be in RAID0 configuration with an ext4 filesystem
sudo yum install -y mdadm
DEVICES=("/dev/nvme1n1" "/dev/nvme2n1" "/dev/nvme3n1" "/dev/nvme4n1")

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
sudo mdadm --create --verbose /dev/md0 --level=0 --name=MY_RAID --raid-devices=4 "${DEVICES[@]}"
sudo mkfs.ext4 -L MY_RAID /dev/md0
sudo mkdir -p /mnt/raid
sudo mount /dev/md0 /mnt/raid
# Ensure the RAID array is mounted automatically at boot
echo "/dev/md0 /mnt/raid ext4 defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab

# Test scenarios for Large, Medium, and Small files adding up to 4 TB
# Large files: 1 GB each
# Medium files: 25 MB each
# Small files: 256 KB each

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
} > /mnt/raid/benchmarks.txt

echo ""
echo "Starting benchmark tests for S3 file operations..." >> /mnt/raid/benchmarks.txt

# Large files test
echo ""
echo "=== Large Files Test ===" >> /mnt/raid/benchmarks.txt
run_tests "large_files" 4096 "1G"

# Medium files test
echo ""
echo "=== Medium Files Test ===" >> /mnt/raid/benchmarks.txt
run_tests "medium_files" 167773 "25M"

# Small files test
echo ""
echo "=== Small Files Test ===" >> /mnt/raid/benchmarks.txt
run_tests "small_files" 16777216 "256K"

echo ""
echo "All tests completed." >> /mnt/raid/benchmarks.txt

s5cmd cp /mnt/raid/benchmarks.txt s3://${SOURCE_BUCKET}/benchmarks.txt
