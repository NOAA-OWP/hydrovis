## Setting up a new Environment

1. Run stage 1 of the root main.tf
2. Populate the deployment bucket with all of the deployment artifacts
3. Add S3 Replication rule to the source S3 bucket
4. Update and import any existnig networking resources into stage 2 modules
5. Run stage 2 of the root main.tf
6. Create and Share Linux AMI to new environment
7. Run EGIS CloudFormation
8. Create EC2 Key Pair `hv-${environment}-ec2-key-pair` in AWS (.pem)
9. Run stage 3 of the root main.tf
10. Do the manual steps on the EGIS License Manager
11. Run stage 4 of the root main.tf