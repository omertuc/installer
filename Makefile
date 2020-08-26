clean:
	./hack/virt-delete-aio.sh || true
	rm -rf mydir

generate:
	mkdir mydir
	cp ./install-config.yaml mydir/
	OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="registry.svc.ci.openshift.org/ocp/release:4.6.0-0.nightly-2020-08-26-215737" ./bin/openshift-install create aio-config --dir=mydir

start:
	./hack/virt-install-aio-ign.sh ./mydir/aio.ign

network:
	./hack/virt-create-net.sh

ssh:
	chmod 400 ./hack/ssh/key
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ./hack/ssh/key core@192.168.126.10

image:
	curl -O -L https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-4.6/46.82.202008181646-0/x86_64/rhcos-46.82.202008181646-0-qemu.x86_64.qcow2.gz
	mv rhcos-46.82.202008181646-0-qemu.x86_64.qcow2.gz /tmp
	sudo gunzip /tmp/rhcos-46.82.202008181646-0-qemu.x86_64.qcow2.gz
