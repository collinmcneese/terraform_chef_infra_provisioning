# Used as an example for running a Chef Infra bootstrap after instance creation.
#  Additional logic used from `main.tf` located within this repository and expects variable data to be created from var.tf (copied from var.tf.example)

# Creat an AWS ec2 instance(s) with supplied data/variables
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

# null_resource to install Chef Infra bootstrap the newly built instance(s)
resource "null_resource" "local_client_bootstrap" {
  # Depend on Security Group creation to allow SSH access to the newly created instance(s)
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

output "local_exec_public_ip" {
  value = aws_instance.chef_local_exec.*.public_ip
}

output "local_exec_public_dns" {
  value = aws_instance.chef_local_exec.*.public_dns
}
