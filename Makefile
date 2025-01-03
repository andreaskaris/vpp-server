CONTAINER_IMAGE ?= quay.io/akaris/vpp-server
MACVLAN_MASTER ?= eno8403np1
VLAN_ID ?= 123
IP_ADDRESS ?= 192.168.123.150/24

.PHONY: build-container
build-container:
	podman build -t $(CONTAINER_IMAGE) .

.PHONY: push-container
push-container:
	podman push $(CONTAINER_IMAGE)

.PHONY: kustomize
kustomize:
	@kustomize build yamls/ | \
		CONTAINER_IMAGE=$(CONTAINER_IMAGE) MACVLAN_MASTER=$(MACVLAN_MASTER) \
		VLAN_ID=$(VLAN_ID) IP_ADDRESS=$(IP_ADDRESS) envsubst

.PHONY: deploy
deploy:
	make kustomize | oc apply -f -

.PHONY: undeploy
undeploy:
	make kustomize | oc delete -f -
