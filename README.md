# Web Server Provision

The script will provison the followoing:
- Two EC2 instances with nginx installed on both
- One S3 bucket with 2 index.html pages.
- One ALB to load balance traffic between the servers according to the URL path provided.


## Technologies

- Bash
- AWS
## Prerequisites

- Install the AWS CLI (apt and yum might not have the up-to-date version since they are 3rd parties repos)
- aws configure with json as the output format
- run the script as a privilage user since the generation of the SSH-Keys requires privileges.
