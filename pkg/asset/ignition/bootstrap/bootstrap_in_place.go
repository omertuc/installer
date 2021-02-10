package bootstrap

import (
	"github.com/openshift/installer/pkg/types"
	"k8s.io/apimachinery/pkg/util/validation/field"
)

// verifyBootstrapInPlace validate the number of control plane replica is one and that installation disk is set
func verifyBootstrapInPlace(installConfig *types.InstallConfig) error {
	errorList := field.ErrorList{}
	if installConfig.BootstrapInPlace == nil {
		return field.Required(field.NewPath("BootstrapInPlace"), "missing BootstrapInPlace configuration")
	}
	if *installConfig.ControlPlane.Replicas != 1 {
		errorList = append(errorList, field.Invalid(field.NewPath("ControlPlane").Child("Replicas"), installConfig.ControlPlane.Replicas,
			"bootstrap in place requires a single ControlPlane replica"))
	}
	if installConfig.BootstrapInPlace.InstallationDisk == "" {
		errorList = append(errorList, field.Invalid(field.NewPath("BootstrapInPlace").Child("InstallationDisk"), installConfig.BootstrapInPlace.InstallationDisk,
			"no InstallationDisk configured for BootstrapInPlace, please set this value to be the target disk drive for the installation"))
	}
	return errorList.ToAggregate()
}
