#!/bin/bash

#################
# Sanity Checks #
#################
# Check if CMDs are installed
command -v jq &>/dev/null || {
  echo "Please install jq (if using mac: brew install jq)"
  exit 1
}

command -v aws &>/dev/null || {
  echo "Please install aws-cli (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
  exit 1
}

command -v sed &>/dev/null || {
  echo "Please install gnu-sed (if using mac: brew instal gnu-sed)"
  exit 1
}

# Check if AWS creds are defined
if ! aws sts get-caller-identity &>/dev/null; then
  echo "AWS Credentials are not set!"
  echo "Configure with aws configure"
  exit 1
fi

###########
#Variables#
###########
SCRIPT_BASEDIR=$(dirname $0)
DEFAULT_VPC_ID="$(aws ec2 describe-vpcs --query 'Vpcs[?IsDefault == `true`].VpcId' --output text)"
INSTANCE_ROLE_NAME=s3-access-to-ec2
BUCKET_NAME=red-blue-html-s3
AMI_ID=ami-05fa00d4c63e32376
KEY_NAME=red_blue_keypair
LOAD_BALANCER_NAME="red-blue-lb"

################
#Access-Control#
################
echo "Creating a key pair in order to access the instances..."
aws ec2 create-key-pair --key-name $KEY_NAME --key-type rsa --query KeyMaterial --output text >$SCRIPT_BASEDIR/$KEY_NAME.pem

echo "Creating IAM role so the instances can access to S3 bucket..."
aws iam create-role --role-name $INSTANCE_ROLE_NAME --assume-role-policy-document "file://$SCRIPT_BASEDIR/assume-role-policy.json"

echo "Attaching S3 Full Access policy to the role created above..."
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --role-name $INSTANCE_ROLE_NAME

echo "Creating IAM instance profile..."
aws iam create-instance-profile --instance-profile-name $INSTANCE_ROLE_NAME

echo "Adding role to instance profile"
aws iam add-role-to-instance-profile --instance-profile-name s3-access-to-ec2 --role-name $INSTANCE_ROLE_NAME 
sleep 5

#################
#Security-Groups#
#################
echo "Creating Security Group to the ALB..."
SG_ID_ALB=$(aws ec2 create-security-group --group-name ALB-SG --description "Security group for the blue/red nginx exercise-ALB" --vpc-id $DEFAULT_VPC_ID | jq -r '.GroupId')
sleep 5
echo "SG ID - $SG_ID_ALB"

sleep 5
echo "Create Security Group Inbound Rule"
aws ec2 authorize-security-group-ingress --group-id $SG_ID_ALB --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "Creating Security Group which allows communication between ALB to EC2 instances..."
SG_ID_EC2=$(aws ec2 create-security-group --group-name EC2-SG --description "Security group for the blue/red nginx exercise-EC2" --vpc-id $DEFAULT_VPC_ID | jq -r '.GroupId')
echo "SG ID - $SG_ID_EC2"

aws ec2 authorize-security-group-ingress --group-id $SG_ID_EC2 --protocol tcp --port 80 --cidr 0.0.0.0/0 

####
#S3#
####
echo "Creating bucket $BUCKET_NAME"
aws s3api create-bucket --bucket $BUCKET_NAME --acl private

mkdir blue red
echo '<h2 style="background-color: steelblue;">My Blue App</h2>' >blue/index.html
echo '<h2 style="background-color: brown; color: bisque;">My Red App</h2>' >red/index.html

echo "sync the newly created folders to the newly created S3..." 
aws s3 sync blue s3://$BUCKET_NAME/blue/ 
aws s3 sync red s3://$BUCKET_NAME/red/ 
rm -rf blue red 

#####
#EC2#
#####
echo "Creating the Blue EC2 Instance..."
BLUE_INSTANCE_ID=$(aws ec2 run-instances --image-id ami-05fa00d4c63e32376 --count 1 --instance-type t2.micro --key-name red_blue_keypair --security-group-ids $SG_ID_EC2 --user-data file://userdata_blue.sh --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=blue}]" --iam-instance-profile Name="$INSTANCE_ROLE_NAME" |jq -r '.Instances[0].InstanceId') 

echo "Creating the Red EC2 Instance..."
RED_INSTANCE_ID=$(aws ec2 run-instances --image-id ami-05fa00d4c63e32376 --count 1 --instance-type t2.micro --key-name red_blue_keypair --security-group-ids $SG_ID_EC2 --user-data file://userdata_red.sh --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=red}]" --iam-instance-profile Name="$INSTANCE_ROLE_NAME" |jq -r '.Instances[0].InstanceId') 

echo "Waiting for Instances to be available..."
sleep 90
echo "Creating target groups for the instances..."

#####
#ALB#
#####
TG_ARN_BLUE=$(aws elbv2 create-target-group --name Blue --protocol HTTP --port 80 --target-type instance --vpc-id $DEFAULT_VPC_ID |jq -r '.TargetGroups[0].TargetGroupArn')
TG_ARN_RED=$(aws elbv2 create-target-group --name Red --protocol HTTP --port 80 --target-type instance --vpc-id $DEFAULT_VPC_ID |jq -r '.TargetGroups[0].TargetGroupArn')

aws elbv2 register-targets --target-group-arn $TG_ARN_BLUE --targets  Id=$BLUE_INSTANCE_ID
aws elbv2 register-targets --target-group-arn $TG_ARN_RED --targets  Id=$RED_INSTANCE_ID

echo "Get Subnets Id"
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filter Name=vpc-id,Values=$DEFAULT_VPC_ID \
  --query 'Subnets[].SubnetId' \
  --output text)


echo "Creating ALB"
ALB_DATA=$(aws elbv2 create-load-balancer \
  --name "red-blue-lb" \
  --subnets $SUBNET_IDS \
  --security-groups $SG_ID_ALB)

sleep 120

echo "Get ALB ARN..."
ALB_ARN=$(aws elbv2 describe-load-balancers --load-balancer-arns | jq -r '.LoadBalancers[0].LoadBalancerArn')
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns | jq -r '.LoadBalancers[0].DNSName')


echo "Creating ALB Listener..."
LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions '[{ "Type": "fixed-response", "FixedResponseConfig": { "MessageBody": "Basa, no colors 🥲", "StatusCode": "503", "ContentType": "text/plain" } }]' |  jq -r '.Listeners[0].ListenerArn')
echo "LISTENER ARN - $LISTENER_ARN"


echo "Edit listener rule for blue route..."
aws elbv2 create-rule --listener-arn $LISTENER_ARN --priority 5 --conditions '[{"Field": "path-pattern","PathPatternConfig": {"Values": ["/blue*"]}}]' --actions Type=forward,TargetGroupArn=$TG_ARN_BLUE

echo "Edit listener rule for red route..."
aws elbv2 create-rule --listener-arn $LISTENER_ARN --priority 4 --conditions '[{"Field": "path-pattern","PathPatternConfig": {"Values": ["/red*"]}}]' --actions Type=forward,TargetGroupArn=$TG_ARN_RED

echo "Waiting for ALB to be available..."
sleep 120

###################################################
echo "!!!!!!!! ALL DONE SUCCSSEFULLY !!!!!!!!"
echo "ALB DNS: $ALB_DNS"

