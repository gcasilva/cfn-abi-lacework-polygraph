#!/bin/bash -ex


## NOTE: paths may differ when running in a managed task. To ensure behavior is consistent between
# managed and local tasks always use these variables for the project and project type path
PROJECT_PATH=${BASE_PATH}/project
PROJECT_TYPE_PATH=${BASE_PATH}/projecttype

cd ${PROJECT_PATH}

cleanup_region() {
    echo "Cleanup running in region: $1"
    export AWS_DEFAULT_REGION=$1
    python3 scripts/cleanup_config.py -C scripts/cleanup_config.json
}

cleanup_all_regions() {
    export AWS_DEFAULT_REGION=us-east-1
    regions=($(aws ec2 describe-regions --query "Regions[*].RegionName" --output text))
    for region in ${regions[@]}
    do
        cleanup_region ${region}
    done
}

run_scoutsuite() {
    #Create Scoutsuite security scan custom rule
    python3 .project_automation/functional_tests/create-scoutsuite-custom-rule.py
    # Execute Scoutsuite security scan
    scout aws -r us-east-1 --ruleset .project_automation/functional_tests/abi-scoutsuite-custom-ruleset.json --no-browser --max-rate 5 --max-workers 5
    # Upload Scoutsuite security scan results to S3 bucket named scoutsuite-results-aws-AWS-ACCOUNT-ID
    python3 .project_automation/functional_tests/process-scoutsuite-report.py
    # Delete taskcat e2e test resources
    taskcat test clean ALL
}

process_scoutsuite_report() {
    # Check Scoutsuite security scan result for Danger level findings (Non-0 exit code)
    scoutsuite_sysout_result=$(cat scoutsuite_sysout.txt)
    #rm scoutsuite_sysout.txt
    if [ "$scoutsuite_sysout_result" -ne 0 ]; then
        # The value is non-zero, indicating Scoutsuite report needs to be checked for security issues
        echo "Scoutsuite report contains security issues. Details below or check the S3 bucket named scoutsuite-results-aws-AWS-ACCOUNT-ID in the test account."
        
        # Retrieve the AWS account ID and store it in a variable
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
        
        # Path to the scoutsuite JSON file
        FILE="./scoutsuite-report/scoutsuite-results/scoutsuite_results_aws-$AWS_ACCOUNT_ID.js"

        # Extract and filter data
        tail -n +2 scoutsuite-report/scoutsuite-results/scoutsuite_results_aws-565009154835.js | jq '.'
        exit 1 
    fi
}

run_test() {
    echo "Running e2e test"
    cleanup_all_regions
    echo $AWS_DEFAULT_REGION
    unset AWS_DEFAULT_REGION
    echo $AWS_DEFAULT_REGION
    taskcat test run -n
    run_scoutsuite
    process_scoutsuite_report
}
# Run taskcat e2e test
run_test

## Executing ash tool

#find ${PROJECT_PATH} -name lambda.zip -exec rm -rf {} \;

#git clone https://github.com/aws-samples/automated-security-helper.git /tmp/ash

# Set the repo path in your shell for easier access
#export PATH=$PATH:/tmp/ash

#ash --source-dir .
#cat aggregated_results.txt

