########################
# User variables
########################

checkenv:
ifndef PULL_SECRET
	$(error PULL_SECRET must be defined)
endif

INSTALLATION_DISK ?= /dev/vda
SSH_KEY_PUB ?= $(shell cat ./hack/sno/ssh/key.pub)
SSH_KEY_PRIV_PATH ?= ./hack/sno/ssh/key

########################

INSTALLER_WORKDIR = mydir
BIP_LIVE_ISO_IGNITION = $(INSTALLER_WORKDIR)/bootstrap-in-place-for-live-iso.ign

INSTALLER_ISO_PATH = ./hack/sno/installer-image.iso
INSTALLER_ISO_PATH_SNO = ./hack/sno/installer-SNO-image.iso

INSTALL_CONFIG_TEMPLATE = ./hack/sno/install-config.yaml.template
INSTALL_CONFIG = ./hack/sno/install-config.yaml
INSTALL_CONFIG_IN_WORKDIR = $(INSTALLER_WORKDIR)/install-config.yaml

NET_CONFIG_TEMPLATE = ./hack/sno/net.xml.template
NET_CONFIG = ./hack/sno/net.xml

OPENSHIFT_RELEASE_IMAGE = quay.io/eranco74/ocp-release:bootstrap-in-place

NET_NAME = test-net
VM_NAME = sno-test
VOL_NAME = $(VM_NAME).qcow2

.PHONY: checkenv clean destroy-libvirt generate embed download-iso start-iso network ssh $(INSTALL_CONFIG)

# $(INSTALL_CONFIG) is also PHONY to force the makefile to regenerate it with new env vars
.PHONY: $(INSTALL_CONFIG)

.SILENT: destroy-libvirt

clean: destroy-libvirt
	rm -rf $(INSTALLER_WORKDIR)

destroy-libvirt:
	echo "Destroying previous libvirt resources"
	NET_NAME=$(NET_NAME) \
        VM_NAME=$(VM_NAME) \
        VOL_NAME=$(VOL_NAME) \
	./hack/sno/virt-delete-sno.sh || true

# Render the install config from the template with the correct pull secret and SSH key
$(INSTALL_CONFIG): $(INSTALL_CONFIG_TEMPLATE) checkenv
	sed -e 's/YOUR_PULL_SECRET/$(PULL_SECRET)/' \
	    -e 's|YOUR_SSH_KEY|$(SSH_KEY_PUB)|' \
	    $(INSTALL_CONFIG_TEMPLATE) > $(INSTALL_CONFIG)

# Render the libvirt net config file with the network name
$(NET_CONFIG): $(NET_CONFIG_TEMPLATE)
	sed -e 's/REPLACE_NET_NAME/$(NET_NAME)/' \
	    $(NET_CONFIG_TEMPLATE) > $@

network: destroy-libvirt $(NET_CONFIG)
	./hack/sno/virt-create-net.sh

# Create a working directory for the openshift-installer `--dir` parameter
$(INSTALLER_WORKDIR):
	mkdir $@

# The openshift-installer expects the install config file to be in its working directory
$(INSTALL_CONFIG_IN_WORKDIR): $(INSTALLER_WORKDIR) $(INSTALL_CONFIG)
	cp $(INSTALL_CONFIG) $@

# Original CoreOS ISO
$(INSTALLER_ISO_PATH): 
	./hack/sno/download_live_iso.sh $@

# Use the openshift-installer to generate BiP Live ISO ignition file
$(BIP_LIVE_ISO_IGNITION): $(INSTALL_CONFIG_IN_WORKDIR)
	OPENSHIFT_INSTALL_EXPERIMENTAL_BOOTSTRAP_IN_PLACE=true \
	OPENSHIFT_INSTALL_EXPERIMENTAL_BOOTSTRAP_IN_PLACE_COREOS_INSTALLER_ARGS=$(INSTALLATION_DISK) \
	OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$(OPENSHIFT_RELEASE_IMAGE)" \
	./bin/openshift-install create ignition-configs --dir=$(INSTALLER_WORKDIR)

# Embed the ignition file in the CoreOS ISO
$(INSTALLER_ISO_PATH_SNO): $(BIP_LIVE_ISO_IGNITION) $(INSTALLER_ISO_PATH)
	# openshift-install will not overwrite existing ISOs, so we delete it beforehand
	rm -f $@

	sudo podman run \
		--pull=always \
		--privileged \
		--rm \
		-v /dev:/dev \
		-v /run/udev:/run/udev \
		-v .:/data \
		--workdir /data \
		quay.io/coreos/coreos-installer:release \
		iso ignition embed /data/$(INSTALLER_ISO_PATH) \
		--force \
		--ignition-file /data/$(BIP_LIVE_ISO_IGNITION) \
		--output /data/$(INSTALLER_ISO_PATH_SNO)

# Destroy previously created VMs/Networks and create a VM/Network with an ISO containing the BiP embedded ignition file
start-iso: $(INSTALLER_ISO_PATH_SNO) network
	RHCOS_ISO=$(INSTALLER_ISO_PATH_SNO) VM_NAME=$(VM_NAME) NET_NAME=$(NET_NAME) ./hack/sno/virt-install-sno-iso-ign.sh

ssh:
	ssh -o IdentityFile=$(SSH_KEY_PRIV_PATH) -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no core@192.168.126.10
