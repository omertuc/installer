package bootstrap

import (
	"github.com/openshift/installer/pkg/types"
	"k8s.io/apimachinery/pkg/util/validation/field"
)

// verifyBootstrapInPlace validate the number of control plane replica is one and that installation disk is set
func verifyBootstrapInPlace(installConfig *types.InstallConfig) error {
	errorList := field.ErrorList{}
	if installConfig.ControlPlane.Replicas == nil {
		errorList = append(errorList, field.Invalid(field.NewPath("controlPlane", "replicas"), installConfig.ControlPlane.Replicas,
			"bootstrap in place requires ControlPlane.Replicas configuration"))
	}
	if *installConfig.ControlPlane.Replicas != 1 {
		errorList = append(errorList, field.Invalid(field.NewPath("controlPlane", "replicas"), installConfig.ControlPlane.Replicas,
			"bootstrap in place requires a single ControlPlane replica"))
	}
	if installConfig.BootstrapInPlace == nil {
		errorList = append(errorList, field.Required(field.NewPath("bootstrapInPlace"), "bootstrapInPlace is required when creating a single node bootstrap-in-place ignition"))
	}
	else if installConfig.BootstrapInPlace.InstallationDisk == "" {
		errorList = append(errorList, field.Required(field.NewPath("bootstrapInPlace", "installationDisk"),
			"installationDisk must be set the target disk drive for the installation"))
	}
	return errorList.ToAggregate()
}
