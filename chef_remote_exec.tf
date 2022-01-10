# Used as an example for running a Chef Infra bootstrap after instance creation.
#  Additional logic used from `main.tf` located within this repository and expects variable data to be created from var.tf (copied from var.tf.example)

# Creat an AWS ec2 instance(s) with supplied data/variables
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

# null_resource to install the Chef Infra Client on built system(s)
resource "null_resource" "chef_remote_install_client" {
  # Depend on Security Group creation to allow SSH access to the newly created instance(s)
  depends_on = [
    aws_instance.chef_remote_exec,
    aws_security_group_rule.internal_sg_traffic,
  ]

  triggers = {
    instance_ids = join(",", aws_instance.chef_remote_exec.*.id)
  }

  count = length(aws_instance.chef_remote_exec.*)

  provisioner "remote-exec" {
    # Download the Chef Software Install Script - https://docs.chef.io/chef_install_script/ and
    #   install Chef Infra Client's latest stable release of version 17.
    inline = [
      "curl -L -o /tmp/chef_install.sh https://omnitruck.chef.io/install.sh",
      "sudo bash /tmp/chef_install.sh -v 17",
    ]
    connection {
      host        = aws_instance.chef_remote_exec[count.index].public_dns
      type        = "ssh"
      user        = var.chef_remote_bootstrap_user
      private_key = file(var.aws_key_file_local)
    }

  }
}

# Stage files on the built instance(s) which will be used during a self-bootstrap
#  Files are staged to tmp location
resource "null_resource" "chef_remote_exec_file_stage" {
  # Depend on Chef Infra Client being installed
  depends_on = [
    null_resource.chef_remote_install_client
  ]

  triggers = {
    instance_ids = join(",", aws_instance.chef_remote_exec.*.id)
  }

  count = length(aws_instance.chef_remote_exec.*)

  provisioner "file" {
    content     = var.chef_bootstrap_clientrb_content
    destination = "/tmp/bootstrap__client.rb"

    connection {
      host        = aws_instance.chef_remote_exec[count.index].public_dns
      type        = "ssh"
      user        = var.chef_remote_bootstrap_user
      private_key = file(var.aws_key_file_local)
    }
  }

  provisioner "file" {
    content     = var.chef_bootstrap_firstbootjson_content
    destination = "/tmp/bootstrap__first-boot.json"

    connection {
      host        = aws_instance.chef_remote_exec[count.index].public_dns
      type        = "ssh"
      user        = var.chef_remote_bootstrap_user
      private_key = file(var.aws_key_file_local)
    }
  }

  provisioner "file" {
    content     = var.chef_bootstrap_pem_content
    destination = "/tmp/bootstrap__validator.pem"

    connection {
      host        = aws_instance.chef_remote_exec[count.index].public_dns
      type        = "ssh"
      user        = var.chef_remote_bootstrap_user
      private_key = file(var.aws_key_file_local)
    }
  }
}

# Relocate the staged files using sudo to proper locations and
#  run self-bootstrap process on the instance(s)
resource "null_resource" "chef_remote_bootstrap" {
  # Depend on Chef Infra Client being installed and bootstrap files being staged
  depends_on = [
    null_resource.chef_remote_install_client,
    null_resource.chef_remote_exec_file_stage
  ]

  triggers = {
    instance_ids = join(",", aws_instance.chef_remote_exec.*.id)
  }

  count = length(aws_instance.chef_remote_exec.*)

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/bootstrap__client.rb /etc/chef/client.rb",
      "sudo mv /tmp/bootstrap__first-boot.json /etc/chef/first-boot.json",
      "sudo mv /tmp/bootstrap__validator.pem /etc/chef/validator.pem",
      "sudo CHEF_LICENSE=accept chef-client -j /etc/chef/first-boot.json",
    ]
    connection {
      host        = aws_instance.chef_remote_exec[count.index].public_dns
      type        = "ssh"
      user        = var.chef_remote_bootstrap_user
      private_key = file(var.aws_key_file_local)
    }

  }
}

output "remote_exec_public_ip" {
  value = aws_instance.chef_remote_exec.*.public_ip
}

output "remote_exec_public_dns" {
  value = aws_instance.chef_remote_exec.*.public_dns
}
