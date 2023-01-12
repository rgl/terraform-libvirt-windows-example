# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.3.7"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source = "hashicorp/random"
      version = "3.4.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.6.14"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  default = "terraform_example"
}

variable "winrm_username" {
  default = "vagrant"
}

variable "winrm_password" {
  sensitive = true
  # set the administrator password.
  # NB the administrator password will be reset to this value by the cloudbase-init SetUserPasswordPlugin plugin.
  # NB this value must meet the Windows password policy requirements.
  #    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
  default = "HeyH0Password"
}

# NB this generates a single random number for the cloud-init instance-id.
resource "random_id" "example" {
  byte_length = 10
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/network.markdown
resource "libvirt_network" "example" {
  name = var.prefix
  mode = "nat"
  domain = "example.test"
  addresses = ["10.17.3.0/24"]
  dhcp {
    enabled = true
  }
  dns {
    enabled = true
    local_only = false
  }
}

# a multipart cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.2/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.2/userdata.html#userdata
# see https://www.terraform.io/docs/providers/template/d/cloudinit_config.html
# see https://www.terraform.io/docs/configuration/expressions.html#string-literals
data "template_cloudinit_config" "example" {
  gzip = false
  base64_encode = false
  part {
    filename = "initialize-disks.ps1"
    content_type = "text/x-shellscript"
    content = <<-EOF
      #ps1_sysnative
      # initialize all (non-initialized) disks with a single NTFS partition.
      # NB we have this script because disk initialization is not yet supported by cloudbase-init.
      # NB the output of this script appears on the cloudbase-init.log file when the
      #    debug mode is enabled, otherwise, you will only have the exit code.
      Get-Disk `
        | Where-Object {$_.PartitionStyle -eq 'RAW'} `
        | ForEach-Object {
          Write-Host "Initializing disk #$($_.Number) ($($_.Size) bytes)..."
          $volume = $_ `
            | Initialize-Disk -PartitionStyle MBR -PassThru `
            | New-Partition -AssignDriveLetter -UseMaximumSize `
            | Format-Volume -FileSystem NTFS -NewFileSystemLabel "disk$($_.Number)" -Confirm:$false
          Write-Host "Initialized disk #$($_.Number) ($($_.Size) bytes) as $($volume.DriveLetter):."
        }
      EOF
  }
  part {
    content_type = "text/cloud-config"
    content = <<-EOF
      #cloud-config
      hostname: example
      timezone: Asia/Tbilisi
      users:
        - name: ${jsonencode(var.winrm_username)}
          passwd: ${jsonencode(var.winrm_password)}
          primary_group: Administrators
          ssh_authorized_keys:
            - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
      # these runcmd commands are concatenated together in a single batch script and then executed by cmd.exe.
      # NB this script will be executed as the cloudbase-init user (which is in the Administrators group).
      # NB this script will be executed by the cloudbase-init service once, but to be safe, make sure its idempotent.
      # NB the output of this script appears on the cloudbase-init.log file when the
      #    debug mode is enabled, otherwise, you will only have the exit code.
      runcmd:
        - "echo # Script path"
        - "echo %~f0"
        - "echo # Sessions"
        - "query session"
        - "echo # whoami"
        - "whoami /all"
        - "echo # Windows version"
        - "ver"
        - "echo # Environment variables"
        - "set"
      EOF
  }
  part {
    filename = "example.ps1"
    content_type = "text/x-shellscript"
    content = <<-EOF
      #ps1_sysnative
      # this is a PowerShell script.
      # NB this script will be executed as the cloudbase-init user (which is in the Administrators group).
      # NB this script will be executed by the cloudbase-init service once, but to be safe, make sure its idempotent.
      # NB the output of this script appears on the cloudbase-init.log file when the
      #    debug mode is enabled, otherwise, you will only have the exit code.
      Start-Transcript -Append "C:\cloudinit-config-example.ps1.log"
      function Write-Title($title) {
        Write-Output "`n#`n# $title`n#"
      }
      Write-Title "Script path"
      Write-Output $PSCommandPath
      Write-Title "Sessions"
      query session | Out-String
      Write-Title "whoami"
      whoami /all | Out-String
      Write-Title "Windows version"
      cmd /c ver | Out-String
      Write-Title "Environment Variables"
      dir env:
      Write-Title "TimeZone"
      Get-TimeZone
      EOF
  }
}

# a cloudbase-init cloud-config disk.
# NB this creates an iso image that will be used by the NoCloud cloudbase-init datasource.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/cloudinit.html.markdown
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/libvirt/cloudinit_def.go#L138-L167
resource "libvirt_cloudinit_disk" "example_cloudinit" {
  name = "${var.prefix}_example_cloudinit.iso"
  meta_data = jsonencode({
    "instance-id": random_id.example.hex,
  })
  user_data = data.template_cloudinit_config.example.rendered
}

# this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/volume.html.markdown
resource "libvirt_volume" "example_root" {
  name = "${var.prefix}_root.img"
  base_volume_name = "windows-2022-amd64_vagrant_box_image_0.0.0_box.img"
  format = "qcow2"
  size = 66*1024*1024*1024 # 66GiB. this root FS is automatically resized by cloudbase-init (by its cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin plugin which is included in the rgl/windows-vagrant image).
}

# a data disk.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/volume.html.markdown
resource "libvirt_volume" "example_data" {
  name = "${var.prefix}_data.img"
  format = "qcow2"
  size = 6*1024*1024*1024 # 6GiB.
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.6.14/website/docs/r/domain.html.markdown
resource "libvirt_domain" "example" {
  name = var.prefix
  cpu {
    mode = "host-passthrough"
  }
  vcpu = 2
  memory = 1024
  video {
    type = "qxl"
  }
  xml {
    xslt = file("libvirt-domain.xsl")
  }
  qemu_agent = true
  cloudinit = libvirt_cloudinit_disk.example_cloudinit.id
  disk {
    volume_id = libvirt_volume.example_root.id
    scsi = false
  }
  disk {
    volume_id = libvirt_volume.example_data.id
    scsi = false
  }
  network_interface {
    network_id = libvirt_network.example.id
    wait_for_lease = true
    hostname = "example"
    addresses = ["10.17.3.2"]
  }
  provisioner "remote-exec" {
    inline = [
      <<-EOF
      rem this is a batch script.
      PowerShell "(Get-Content C:/cloudinit-config-example.ps1.log) -replace '^','C:/cloudinit-config-example.ps1.log: '"
      query session
      whoami /all
      ver
      PowerShell "Get-Disk | Select-Object Number,PartitionStyle,Size | Sort-Object Number"
      PowerShell "Get-Volume | Sort-Object DriveLetter,FriendlyName"
      EOF
    ]
    connection {
      type = "winrm"
      user = var.winrm_username
      password = var.winrm_password
      host = self.network_interface[0].addresses[0] # see https://github.com/dmacvicar/terraform-provider-libvirt/issues/660
      timeout = "1h"
    }
  }
}

output "ip" {
  value = length(libvirt_domain.example.network_interface[0].addresses) > 0 ? libvirt_domain.example.network_interface[0].addresses[0] : ""
}
