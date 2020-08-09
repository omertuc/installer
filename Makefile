clean:
	./hack/virt-delete-aio.sh || true
	rm -rf mydir
	mkdir mydir
	cp ../install-config.yaml mydir/

generate:
	./bin/openshift-install create ignition-configs --dir=mydir

start:
	./hack/virt-install-aio-ign.sh ./mydir/bootstrap.ign

ssh:
	ssh -i ~/.ssh/id_rsa core@$(shell sudo virsh net-dhcp-leases default | grep `sudo virsh dumpxml aio-test| grep 52:54:00 | awk -F "'" '{print $$2}'` | awk '{print $$5}' | awk -F "/" '{print $$1}')

