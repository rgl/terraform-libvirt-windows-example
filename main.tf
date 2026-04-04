# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.14.8"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.7"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  default = "terraform-windows-example"
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

# NB this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
variable "base_volume_name" {
  default = "windows-2022-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  # default = "windows-2025-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  # default = "windows-11-24h2-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

variable "network_cidr" {
  type    = string
  default = "10.17.5.0/24"
}

# NB this generates a single random number for the cloud-init instance-id.
resource "random_id" "example" {
  byte_length = 10
}

# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-2k22.xml.in
# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-2k25.xml.in
# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-11.xml.in
locals {
  windows_version = regex("windows-([^-]+)", var.base_volume_name)[0]
  windows_version_to_os_map = {
    "2022" = "2k22"
    "2025" = "2k25"
    "11"   = "11"
  }
  os_id = "http://microsoft.com/win/${lookup(local.windows_version_to_os_map, local.windows_version, "2k22")}"
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.7/docs/resources/network
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/docs/resources/network.md
resource "libvirt_network" "example" {
  name = var.prefix
  forward = {
    nat = {
      ports = [
        {
          start = 1024
          end   = 65535
        }
      ]
    }
  }
  domain = {
    name = "example.test"
  }
  ips = [
    {
      address = cidrhost(var.network_cidr, 1)
      netmask = cidrnetmask(var.network_cidr)
      dhcp = {
        ranges = [
          {
            start = cidrhost(var.network_cidr, 2)
            end   = cidrhost(var.network_cidr, -2)
          }
        ]
      }
    }
  ]
}

# a multipart cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.2/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.2/userdata.html#userdata
# see https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config
# see https://www.terraform.io/docs/configuration/expressions.html#string-literals
data "cloudinit_config" "example" {
  gzip          = false
  base64_encode = false
  part {
    filename     = "initialize-disks.ps1"
    content_type = "text/x-shellscript"
    content      = <<-EOF
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
    content      = <<-EOF
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
    filename     = "example.ps1"
    content_type = "text/x-shellscript"
    content      = <<-EOF
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
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.7/docs/resources/cloudinit_disk
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/docs/resources/cloudinit_disk.md
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/internal/provider/cloudinit_disk_resource.go#L291-L341
resource "libvirt_cloudinit_disk" "example_cloudinit" {
  name = "${var.prefix}-cloudinit.iso"
  meta_data = jsonencode({
    "instance-id" : random_id.example.hex,
  })
  user_data = data.cloudinit_config.example.rendered
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.7/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/docs/resources/volume.md
resource "libvirt_volume" "example_cloudinit" {
  pool = "default"
  name = "${var.prefix}-cloudinit.iso"
  create = {
    content = {
      url = libvirt_cloudinit_disk.example_cloudinit.path
    }
  }
}

# this uses the vagrant debian image imported from https://github.com/rgl/debian-vagrant.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.7/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/docs/resources/volume.md
resource "libvirt_volume" "example_root" {
  pool     = "default"
  name     = "${var.prefix}-root.img"
  capacity = 66 * 1024 * 1024 * 1024 # 66GiB. this root FS is automatically resized by cloudbase-init (by its cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin plugin which is included in the rgl/windows-vagrant image).
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    format = {
      type = "qcow2"
    }
    path = "/var/lib/libvirt/images/${var.base_volume_name}"
  }
}

# a data disk.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.7/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/docs/resources/volume.md
resource "libvirt_volume" "example_data" {
  pool     = "default"
  name     = "${var.prefix}-data.img"
  capacity = 6 * 1024 * 1024 * 1024 # 6GiB.
  target = {
    format = {
      type = "qcow2"
    }
  }
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.7/website/docs/r/domain.html.markdown
resource "libvirt_domain" "example" {
  name        = var.prefix
  description = "created from ${path.cwd}"
  running     = true
  type        = "kvm"
  vcpu        = 2
  memory      = 1024
  memory_unit = "MiB"
  features = {
    acpi = true
    apic = {}
    pae  = true
  }
  metadata = {
    xml = <<-EOF
      <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
        <libosinfo:os id="${local.os_id}"/>
      </libosinfo:libosinfo>
      EOF
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }
  cpu = {
    mode = "host-passthrough"
  }
  devices = {
    graphics = [
      {
        spice = {
          auto_port = true
          listeners = [
            {
              address = {}
            }
          ]
        }
      }
    ]
    videos = [
      {
        model = {
          type    = "qxl"
          primary = "yes"
          vram    = 65536
          ram     = 65536
          vga_mem = 16384
          heads   = 1
        }
      }
    ]
    controllers = [
      {
        type  = "scsi"
        model = "virtio-scsi"
      },
      {
        type = "virtio-serial"
      }
    ]
    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      },
      {
        source = {
          spice_vmc = true
        }
        target = {
          virt_io = {
            name = "com.redhat.spice.0"
          }
        }
      }
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.example_root.pool
            volume = libvirt_volume.example_root.name
          }
        }
        target = {
          bus = "scsi"
          dev = "sda"
        }
        wwn = format("000000000000aa%02x", 0)
      },
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.example_data.pool
            volume = libvirt_volume.example_data.name
          }
        }
        target = {
          bus = "scsi"
          dev = "sdb"
        }
        wwn = format("000000000000ab%02x", 0)
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.example_cloudinit.pool
            volume = libvirt_volume.example_cloudinit.name
          }
        }
        target = {
          bus = "scsi"
          dev = "hdd"
        }
        serial = "cloudinit"
      }
    ]
    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.example.name
          }
        }
        # TODO https://github.com/dmacvicar/terraform-provider-libvirt/issues/1323
        wait_for_ip = {
          source  = "agent"
          timeout = 300 # 300s (5m).
        }
      }
    ]
  }
}

# see https://developer.hashicorp.com/terraform/language/resources/terraform-data
resource "terraform_data" "example_provision" {
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
      type     = "winrm"
      user     = var.winrm_username
      password = var.winrm_password
      host     = one(flatten([for interface in data.libvirt_domain_interface_addresses.example.interfaces : [for addr in interface.addrs : addr.addr if addr.type == "ipv4" && addr.addr != "127.0.0.1"]]))
      timeout  = "1h"
    }
  }
}

# TODO https://github.com/dmacvicar/terraform-provider-libvirt/issues/1323
data "libvirt_domain_interface_addresses" "example" {
  domain = libvirt_domain.example.name
  source = "agent"
}

output "ip" {
  value = one(flatten([for interface in data.libvirt_domain_interface_addresses.example.interfaces : [for addr in interface.addrs : addr.addr if addr.type == "ipv4" && addr.addr != "127.0.0.1"]]))
}
