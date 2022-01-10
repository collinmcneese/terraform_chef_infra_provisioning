# Provisioning Chef Infra with Terraform

Historically, provisioners existed with Terraform, by HashiCorp, for the execution of Chef Infra within a Terraform plan.  With the `0.13.4` release of Terraform, many external provisioners were deprecated, including the Chef provisioner, and as of Terraform `0.15.0` these deprecated provisioners no longer function so alternative methods must be used which are more native to Terraform workflows and resources.

Luckily, Chef Infra still works very well together with Terraform using updated patterns, allowing for Terraform to be used for provisioning of infrastructure resources including the execution of Chef components by making use of `remote-exec` or `local-exec` provisioners within Terraform.

## Chef Infra Provisioning

Terraform provisioning of Chef Infra components can be used in a number of ways to best support the needs of the deployment type for systems which are "bootstraped" or run in a standalone model.

### Chef Infra Bootstrap With `remote-exec`

This method relies upon creating the provisioned instance/vm and then:

* Installing the Chef Infra Client
* Staging any files which are needed on the client for a self-bootstrap using the Terraform `file` provisioner
  * Examples are `validator` PEM contents, `config.rb` contents for the Chef Infra Client and a `first-boot.json` file to use for initial configuration details.
* Running the Chef Infra Client to complete setup using the Terraform `remote-exec` provisioner:

A detailed example of this configuration is located within [chef_remote_exec](chef_remote_exec.tf)

Example reference of an AWS EC2 instance creation resource:

```terraform
resource "aws_instance" "chef_remote_exec" {
  ami                         = data.aws_ami.amazon-linux-2.id
  count                       = length(var.chef_remote_exec_servers)
  instance_type               = var.aws_instance_type
  vpc_security_group_ids      = [aws_security_group.amz_server_sg.id]
  associate_public_ip_address = true
  key_name                    = var.aws_key
  subnet_id                   = var.aws_subnet_id

  tags = var.aws_tags
}
```

Using a `null_resource` to install Chef Infra Client:

```terraform
resource "null_resource" "chef_remote_install_client" {
  depends_on = [
    aws_instance.chef_remote_exec,
    aws_security_group_rule.internal_sg_traffic,
  ]

  triggers = {
    instance_ids = join(",", aws_instance.chef_remote_exec.*.id)
  }

  count = length(aws_instance.chef_remote_exec.*)

  provisioner "remote-exec" {
    inline = [
      "curl -L -o /tmp/chef_client_install.sh https://omnitruck.chef.io/install.sh",
      "sudo bash /tmp/chef_client_install.sh -v 17",
    ]
    connection {
      host        = aws_instance.chef_remote_exec[count.index].public_dns
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.aws_key_file_local)
    }

  }
}
```

### Chef Infra Bootstrap With `local-exec`

This method uses Chef Workstation for executing remote processes by relies upon creating the provisioned instance/vm and then:

* Uses Chef Workstation installed locally where Terraform code is executed to run a remote bootstrap using `knife`
  * Requires local configuration to be present (or provided as variables during execution time) for configuration parameters.

A detailed example of this configuration is located within [chef_local_exec](chef_local_exec.tf)

Example reference of an AWS EC2 instance creation resource:

```terraform
resource "aws_instance" "chef_local_exec" {
  ami                         = data.aws_ami.amazon-linux-2.id
  count                       = length(var.chef_local_exec_servers)
  instance_type               = var.aws_instance_type
  vpc_security_group_ids      = [aws_security_group.amz_server_sg.id]
  associate_public_ip_address = true
  key_name                    = var.aws_key
  subnet_id                   = var.aws_subnet_id

  tags = var.aws_tags
}
```

Using a `null_resource` to execute a remote Chef Infra bootstrap:

```terraform
resource "null_resource" "local_client_bootstrap" {
  depends_on = [
    aws_instance.chef_local_exec,
    aws_security_group_rule.internal_sg_traffic,
  ]

  triggers = {
    instance_ids = join(",", aws_instance.chef_local_exec.*.id)
  }

  count = length(aws_instance.chef_local_exec.*)

  provisioner "local-exec" {
    command = <<-LOCAL
      knife bootstrap ${var.chef_remote_bootstrap_user}@${aws_instance.chef_local_exec[count.index].public_ip} \
        -N ${aws_instance.chef_local_exec[count.index].public_dns} \
        -i ${var.aws_key_file_local} \
        --sudo \
        --policy-group dev \
        --policy-name bootstrap_policy \
        -y \
        -c ${var.chef_workstation_config_path}
    LOCAL
  }
}
```

## Self-Bootstrap using remote-exec

Output from running the provided `chef_remote_exec.tf` plan to build instance(s) and self-bootstrap:

```plain
aws_security_group.amz_server_sg: Creating...
aws_security_group.amz_server_sg: Creation complete after 3s [id=sg-00000]
aws_security_group_rule.internal_sg_traffic: Creating...
aws_security_group_rule.egress_rule: Creating...
aws_security_group_rule.ingress_ssh_rule: Creating...
aws_instance.chef_remote_exec[0]: Creating...
aws_security_group_rule.internal_sg_traffic: Creation complete after 1s [id=sgrule-00000]
aws_security_group_rule.ingress_ssh_rule: Creation complete after 2s [id=sgrule-00000]
aws_security_group_rule.egress_rule: Creation complete after 3s [id=sgrule-00000]
aws_instance.chef_remote_exec[0]: Still creating... [10s elapsed]
aws_instance.chef_remote_exec[0]: Creation complete after 14s [id=i-00000]
null_resource.chef_remote_install_client[0]: Creating...
null_resource.chef_remote_install_client[0]: Provisioning with 'remote-exec'...
null_resource.chef_remote_install_client[0] (remote-exec): Connecting to remote host via SSH...
null_resource.chef_remote_install_client[0] (remote-exec):   Host: ec2-172-17-100-100.us-west-2.compute.amazonaws.com
null_resource.chef_remote_install_client[0] (remote-exec):   User: ec2-user
null_resource.chef_remote_install_client[0] (remote-exec):   Password: false
null_resource.chef_remote_install_client[0] (remote-exec):   Private key: true
null_resource.chef_remote_install_client[0] (remote-exec):   Certificate: false
null_resource.chef_remote_install_client[0] (remote-exec):   SSH Agent: true
null_resource.chef_remote_install_client[0] (remote-exec):   Checking Host Key: false
null_resource.chef_remote_install_client[0] (remote-exec):   Target Platform: unix
null_resource.chef_remote_install_client[0] (remote-exec): Connected!
null_resource.chef_remote_install_client[0] (remote-exec):   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
null_resource.chef_remote_install_client[0] (remote-exec):                                  Dload  Upload   Total   Spent    Left  Speed
null_resource.chef_remote_install_client[0] (remote-exec):   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
null_resource.chef_remote_install_client[0] (remote-exec): 100 23409  100 23409    0     0   275k      0 --:--:-- --:--:-- --:--:--  278k
null_resource.chef_remote_install_client[0] (remote-exec): el 7 x86_64
null_resource.chef_remote_install_client[0] (remote-exec): Getting information for chef stable 17 for el...
null_resource.chef_remote_install_client[0] (remote-exec): downloading https://omnitruck.chef.io/stable/chef/metadata?v=17&p=el&pv=7&m=x86_64
null_resource.chef_remote_install_client[0] (remote-exec):   to file /tmp/install.sh.2562/metadata.txt
null_resource.chef_remote_install_client[0] (remote-exec): trying wget...
null_resource.chef_remote_install_client[0] (remote-exec): sha1 305520305206c7c0fb5a733b1435359e7707be83
null_resource.chef_remote_install_client[0] (remote-exec): sha256       70d618fbf5633b9f819b5cdc9a422403bc47690ae63cc383a83462cbbd387245
null_resource.chef_remote_install_client[0] (remote-exec): url  https://packages.chef.io/files/stable/chef/17.9.26/el/7/chef-17.9.26-1.el7.x86_64.rpm
null_resource.chef_remote_install_client[0] (remote-exec): version      17.9.26
null_resource.chef_remote_install_client[0] (remote-exec): downloaded metadata file looks valid...
null_resource.chef_remote_install_client[0] (remote-exec): downloading https://packages.chef.io/files/stable/chef/17.9.26/el/7/chef-17.9.26-1.el7.x86_64.rpm
null_resource.chef_remote_install_client[0] (remote-exec):   to file /tmp/install.sh.2562/chef-17.9.26-1.el7.x86_64.rpm
null_resource.chef_remote_install_client[0] (remote-exec): trying wget...
null_resource.chef_remote_install_client[0] (remote-exec): Comparing checksum with sha256sum...
null_resource.chef_remote_install_client[0] (remote-exec): Installing chef 17
null_resource.chef_remote_install_client[0] (remote-exec): installing with rpm...
null_resource.chef_remote_install_client[0] (remote-exec): warning: /tmp/install.sh.2562/chef-17.9.26-1.el7.x86_64.rpm: Header V4 DSA/SHA1 Signature, key ID 83ef826a: NOKEY
null_resource.chef_remote_install_client[0] (remote-exec): Preparing...
null_resource.chef_remote_install_client[0] (remote-exec): ################################# [100%]
null_resource.chef_remote_install_client[0] (remote-exec): Updating / installing...
null_resource.chef_remote_install_client[0] (remote-exec):    1:chef-17.9.26-1.el7                                                 (  2%)
null_resource.chef_remote_install_client[0] (remote-exec): #                                 (  4%)
... truncated ...
null_resource.chef_remote_install_client[0] (remote-exec): ################################# [100%]
null_resource.chef_remote_install_client[0] (remote-exec): Thank you for installing Chef Infra Client! For help getting started visit https://learn.chef.io
null_resource.chef_remote_install_client[0]: Still creating... [10s elapsed]
null_resource.chef_remote_install_client[0]: Creation complete after 11s [id=535125365393635558]
null_resource.chef_remote_exec_file_stage[0]: Creating...
null_resource.chef_remote_exec_file_stage[0]: Provisioning with 'file'...
null_resource.chef_remote_exec_file_stage[0]: Provisioning with 'file'...
null_resource.chef_remote_exec_file_stage[0]: Provisioning with 'file'...
null_resource.chef_remote_exec_file_stage[0]: Creation complete after 2s [id=8184009876103595537]
null_resource.chef_remote_bootstrap[0]: Creating...
null_resource.chef_remote_bootstrap[0]: Provisioning with 'remote-exec'...
null_resource.chef_remote_bootstrap[0] (remote-exec): Connecting to remote host via SSH...
null_resource.chef_remote_bootstrap[0] (remote-exec):   Host: ec2-172-17-100-100.us-west-2.compute.amazonaws.com
null_resource.chef_remote_bootstrap[0] (remote-exec):   User: ec2-user
null_resource.chef_remote_bootstrap[0] (remote-exec):   Password: false
null_resource.chef_remote_bootstrap[0] (remote-exec):   Private key: true
null_resource.chef_remote_bootstrap[0] (remote-exec):   Certificate: false
null_resource.chef_remote_bootstrap[0] (remote-exec):   SSH Agent: true
null_resource.chef_remote_bootstrap[0] (remote-exec):   Checking Host Key: false
null_resource.chef_remote_bootstrap[0] (remote-exec):   Target Platform: unix
null_resource.chef_remote_bootstrap[0] (remote-exec): Connected!
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:29+00:00] INFO: Persisting a license for Chef Infra Client at path /etc/chef/accepted_licenses/chef_infra_client
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:29+00:00] INFO: Persisting a license for Chef InSpec at path /etc/chef/accepted_licenses/inspec
null_resource.chef_remote_bootstrap[0] (remote-exec): +---------------------------------------------+
null_resource.chef_remote_bootstrap[0] (remote-exec): ✔ 2 product licenses accepted.
null_resource.chef_remote_bootstrap[0] (remote-exec): +---------------------------------------------+
null_resource.chef_remote_bootstrap[0] (remote-exec): Chef Infra Client, version 17.9.26
null_resource.chef_remote_bootstrap[0] (remote-exec): Patents: https://www.chef.io/patents
null_resource.chef_remote_bootstrap[0] (remote-exec): Infra Phase starting
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:29+00:00] INFO: *** Chef Infra Client 17.9.26 ***
... truncated ...
null_resource.chef_remote_bootstrap[0] (remote-exec):   * service[chef-client] action restart[2022-01-10T20:19:36+00:00] INFO: Processing service[chef-client] action restart (chef-client::systemd_service line 93)
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:36+00:00] INFO: service[chef-client] restarted
null_resource.chef_remote_bootstrap[0] (remote-exec):     - restart service service[chef-client]
null_resource.chef_remote_bootstrap[0]: Still creating... [10s elapsed]
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:37+00:00] INFO: Chef Infra Client Run complete in 4.840334064 seconds
null_resource.chef_remote_bootstrap[0] (remote-exec): Running handlers:
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:37+00:00] INFO: Running report handlers
null_resource.chef_remote_bootstrap[0] (remote-exec): Running handlers complete
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:37+00:00] INFO: Report handlers complete
null_resource.chef_remote_bootstrap[0] (remote-exec): Infra Phase complete, 9/14 resources updated in 07 seconds
null_resource.chef_remote_bootstrap[0] (remote-exec): [2022-01-10T20:19:37+00:00] INFO: Sending resource update report (run-id: e087d0bb-a9cf-40a6-8d5e-9a9e7435fde6)
null_resource.chef_remote_bootstrap[0]: Creation complete after 11s [id=9120719189337636816]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

## Knife Bootstrap using local-exec

Output from running the provided `chef_local_exec.tf` plan to build instance(s) and self-bootstrap:

```plain
null_resource.local_client_bootstrap[0]: Creating...
null_resource.local_client_bootstrap[0]: Provisioning with 'local-exec'...
null_resource.local_client_bootstrap[0] (local-exec): Executing: ["/bin/sh" "-c" "knife bootstrap ec2-user@172.17.99.99 -N ec2-172-17-99-99.us-west-2.compute.amazonaws.com -i /path/to/my-aws-keypair.pem  --sudo --policy-group dev --policy-name bootstrap_policy -y -c /path/to/chef-repo/.chef/config.rb\n"]
null_resource.local_client_bootstrap[0] (local-exec): Connecting to 172.17.99.99 using ssh
null_resource.local_client_bootstrap[0] (local-exec): Connecting to 172.17.99.99 using ssh
null_resource.local_client_bootstrap[0]: Still creating... [10s elapsed]
null_resource.local_client_bootstrap[0] (local-exec): Creating new client for ec2-172-17-99-99.us-west-2.compute.amazonaws.com
null_resource.local_client_bootstrap[0] (local-exec): Creating new node for ec2-172-17-99-99.us-west-2.compute.amazonaws.com
null_resource.local_client_bootstrap[0] (local-exec): Bootstrapping 172.17.99.99
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] -----> Installing Chef Omnibus (stable/17)
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] downloading https://omnitruck.chef.io/chef/install.sh
null_resource.local_client_bootstrap[0] (local-exec):   to file /tmp/install.sh.2709/install.sh
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] trying wget...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] el 7 x86_64
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Getting information for chef stable 17 for el...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] downloading https://omnitruck-direct.chef.io/stable/chef/metadata?v=17&p=el&pv=7&m=x86_64
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99]   to file /tmp/install.sh.2714/metadata.txt
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] trying wget...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] sha1     33a1cba10df320877a7dc0b163c0055e933d7efd
null_resource.local_client_bootstrap[0] (local-exec): sha256    6104980b2fbe0518f0dd8fd852bdf2c46f90d795d3a5f616c9c219f7ff77ec29
null_resource.local_client_bootstrap[0] (local-exec): url       https://packages.chef.io/files/stable/chef/17.4.38/el/7/chef-17.4.38-1.el7.x86_64.rpm
null_resource.local_client_bootstrap[0] (local-exec): version   17.4.38
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99]
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] downloaded metadata file looks valid...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] downloading https://packages.chef.io/files/stable/chef/17.4.38/el/7/chef-17.4.38-1.el7.x86_64.rpm
null_resource.local_client_bootstrap[0] (local-exec):   to file /tmp/install.sh.2714/chef-17.4.38-1.el7.x86_64.rpm
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] trying wget...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Comparing checksum with sha256sum...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Installing chef 17
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] installing with rpm...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] warning: /tmp/install.sh.2714/chef-17.4.38-1.el7.x86_64.rpm: Header V4 DSA/SHA1 Signature, key ID 83ef826a: NOKEY
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Preparing...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] ########################################
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Updating / installing...
null_resource.local_client_bootstrap[0] (local-exec): chef-17.4.38-1.el7
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] #
... truncated ...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] #
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Thank you for installing Chef Infra Client! For help getting started visit https://learn.chef.io
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Starting the first Chef Infra Client Client run...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] +---------------------------------------------+
null_resource.local_client_bootstrap[0] (local-exec): ✔ 2 product licenses accepted.
null_resource.local_client_bootstrap[0] (local-exec): +---------------------------------------------+
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Chef Infra Client, version 17.4.38
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Patents: https://www.chef.io/patents
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Infra Phase starting
null_resource.local_client_bootstrap[0]: Still creating... [20s elapsed]
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Using Policyfile 'bootstrap_policy' at revision '973392110e434b6ddd421e263888f2d2e262a1e8f77c912bb620869fbadf4c5c'
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Resolving cookbooks for run list: ["chef-client::default@12.3.4 (9e41484)"]
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Synchronizing cookbooks:
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99]   - chef-client (12.3.4)
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Installing cookbook gem dependencies:
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Compiling cookbooks...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Converging 9 resources
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Recipe: chef-client::systemd_service
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99]   * directory[/var/run/chef] action create
null_resource.local_client_bootstrap[0] (local-exec):     - create new directory /var/run/chef
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] - change owner from '' to 'root'
null_resource.local_client_bootstrap[0] (local-exec):     - change group from '' to 'root'
... truncated ...
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] - restart service service[chef-client]
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99]
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99]
null_resource.local_client_bootstrap[0] (local-exec): Running handlers:
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Running handlers complete
null_resource.local_client_bootstrap[0] (local-exec):  [172.17.99.99] Infra Phase complete, 9/14 resources updated in 07 seconds
null_resource.local_client_bootstrap[0]: Creation complete after 27s [id=9131490459522292962]
```
