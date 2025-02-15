# Usage (Ubuntu 22.04 host)

**NB** For using Ansible as a provisioner see the [rgl/terraform-libvirt-ansible-windows-example repository](https://github.com/rgl/terraform-libvirt-ansible-windows-example).

Create and install the [UEFI Windows 2022 vagrant box](https://github.com/rgl/windows-vagrant).

Install Terraform:

```bash
wget https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
unzip terraform_1.9.8_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Create the infrastructure:

```bash
terraform init
terraform plan -out=tfplan
time terraform apply tfplan
```

**NB** if you have errors alike `Could not open '/var/lib/libvirt/images/terraform_example_root.img': Permission denied'` you need to reconfigure libvirt by setting `security_driver = "none"` in `/etc/libvirt/qemu.conf` and restart libvirt with `sudo systemctl restart libvirtd`.

Show information about the libvirt/qemu guest:

```bash
virsh dumpxml terraform_example
virsh qemu-agent-command terraform_example '{"execute":"guest-info"}' --pretty
virsh qemu-agent-command terraform_example '{"execute":"guest-network-get-interfaces"}' --pretty
./qemu-agent-guest-exec terraform_example winrm enumerate winrm/config/listener
./qemu-agent-guest-exec terraform_example winrm get winrm/config
```

Login into the machine using SSH:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "$(terraform output --raw ip)"
ssh "vagrant@$(terraform output --raw ip)"
sshd -V # show the sshd version.
ssh -V  # show the ssh version.
exit # ssh
```

Login into the machine using PowerShell Remoting over SSH:

```bash
pwsh
Enter-PSSession -HostName "vagrant@$(terraform output --raw ip)"
$PSVersionTable
whoami /all
exit # Enter-PSSession
exit # pwsh
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```

List this repository dependencies (and which have newer versions):

```bash
GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN' ./renovate.sh
```

# Virtual BMC

You can externally control the VM using the following terraform providers:

* [vbmc terraform provider](https://registry.terraform.io/providers/rgl/vbmc)
  * exposes an [IPMI](https://en.wikipedia.org/wiki/Intelligent_Platform_Management_Interface) endpoint.
  * you can use it with [ipmitool](https://github.com/ipmitool/ipmitool).
  * for more information see the [rgl/terraform-provider-vbmc](https://github.com/rgl/terraform-provider-vbmc) repository.
* [sushy-vbmc terraform provider](https://registry.terraform.io/providers/rgl/sushy-vbmc)
  * exposes a [Redfish](https://en.wikipedia.org/wiki/Redfish_(specification)) endpoint.
  * you can use it with [redfishtool](https://github.com/DMTF/Redfishtool).
  * for more information see the [rgl/terraform-provider-sushy-vbmc](https://github.com/rgl/terraform-provider-sushy-vbmc) repository.
