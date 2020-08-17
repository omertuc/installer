clean:
	./hack/virt-delete-aio.sh || true
	rm -rf mydir

generate:
	mkdir mydir
	cp ../install-config.yaml mydir/
	./bin/openshift-install create aio-config --dir=mydir

start:
	./hack/virt-install-aio-ign.sh ./mydir/aio.ign

network:
	./hack/virt-create-net.sh

ssh:
	#ssh -i ~/.ssh/id_rsa core@$(shell sudo virsh net-dhcp-leases default | grep `sudo virsh dumpxml aio-test| grep 52:54:00 | awk -F "'" '{print $$2}'` | awk '{print $$5}' | awk -F "/" '{print $$1}')
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa core@192.168.126.10
