package bootstrap

import (
	"github.com/pkg/errors"

	"github.com/openshift/installer/pkg/types"
)

// verifyBootstrapInPlace validate the number of control plane replica is one and that installation disk is set
func verifyBootstrapInPlace(installConfig *types.InstallConfig) error {
	if *installConfig.ControlPlane.Replicas != 1 {
		return errors.Errorf("bootstrap in place requires a single ControlPlane replica, current value: %d", *installConfig.ControlPlane.Replicas)
	}
	if installConfig.BootstrapInPlace == nil {
		return errors.Errorf("missing BootstrapInPlace configuration")
	}
	if installConfig.BootstrapInPlace.InstallationDisk == "" {
		return errors.Errorf("no InstallationDisk configured for BootstrapInPlace, please set this value to be the target disk drive for the installation")
	}
	return nil
}
