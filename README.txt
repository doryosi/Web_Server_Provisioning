The script will do the following:
1. Provision 2 EC2 Nginx Servers that Host 2 different "applicaiton".
2. Provision an S3 Bucket
3. Provison Application Load Balancer that forwards requests to each site according to the path specified within the url field on the browser.

Prerequisites:
1. Install the AWS CLI (apt and yum might not have the up-to-date version since they are 3rd parties repos)
2. aws configure with json as the output format
3. run the script as a privilage user since the generation of the SSH-Keys requires privileges.


