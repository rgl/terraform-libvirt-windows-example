# syntax=docker.io/docker/dockerfile:1.13

# see https://github.com/PowerShell/PowerShell/releases
# renovate: datasource=github-releases depName=PowerShell/PowerShell extractVersion=^v(?<version>7\.4\..+)
ARG POWERSHELL_VERSION='7.4.7'

# see https://github.com/hashicorp/terraform/releases
# renovate: datasource=github-releases depName=hashicorp/terraform
ARG TERRAFORM_VERSION='1.10.5'

# see https://github.com/devcontainers/images/tree/main/src/base-debian/history
FROM mcr.microsoft.com/devcontainers/base:1.0.19-bookworm

RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install --no-install-recommends \
    bash-completion \
    curl \
    git \
    libvirt-clients \
    mkisofs \
    openssh-client \
    python3-argcomplete \
    python3-libvirt \
    sudo \
    unzip \
    wget \
    xorriso \
    xsltproc
apt-get clean
rm -rf /var/lib/apt/lists/*
activate-global-python-argcomplete
EOF

ARG POWERSHELL_VERSION
ENV POWERSHELL_TELEMETRY_OPTOUT=1
ENV POWERSHELL_UPDATECHECK=Off
RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
dist_name="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
wget -qO /etc/apt/keyrings/packages.microsoft.com.asc https://packages.microsoft.com/keys/microsoft.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.com.asc] https://packages.microsoft.com/repos/microsoft-$dist_name-$(lsb_release -cs)-prod $(lsb_release -cs) main" >/etc/apt/sources.list.d/packages.microsoft.com.list
apt-get update
package_version="$(apt-cache madison powershell | awk "/$POWERSHELL_VERSION/{print \$3}")"
apt-get install -y "powershell=$package_version"
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

ARG TERRAFORM_VERSION
ENV CHECKPOINT_DISABLE=1
RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
terraform_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
t="$(mktemp -q -d --suffix=.terraform)"
wget -qO "$t/terraform.zip" "$terraform_url"
unzip "$t/terraform.zip" -d "$t"
install "$t/terraform" /usr/local/bin
rm -rf "$t"
terraform -install-autocomplete
EOF

RUN <<'EOF'
#!/usr/bin/bash
set -euxo pipefail
# ensure /etc/profile is called at the top of the file, when running in a
# login shell.
sed -i '0,/esac/s/esac/&\n\nsource \/etc\/profile/' /home/vscode/.bashrc
EOF
COPY inputrc /etc/inputrc
COPY login.sh /etc/profile.d/login.sh
