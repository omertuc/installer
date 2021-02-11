package bootstrap

import (
	"encoding/json"
	"os"

	igntypes "github.com/coreos/ignition/v2/config/v3_1/types"
	"github.com/openshift/installer/pkg/asset"
	"github.com/openshift/installer/pkg/asset/installconfig"
	"github.com/openshift/installer/pkg/types"
	"github.com/pkg/errors"
	"k8s.io/apimachinery/pkg/util/validation/field"
)

const (
	bootstrapInPlaceIgnFilename = "bootstrap-in-place-for-live-iso.ign"
)

// BootstrapInPlace is the asset for the ironic user credentials
type BootstrapInPlace struct {
	File   *asset.File
	Config *igntypes.Config
}

var _ asset.Asset = (*BootstrapInPlace)(nil)

// Dependencies returns no dependencies.
func (a *BootstrapInPlace) Dependencies() []asset.Asset {
	b := Bootstrap{BootstrapInPlace: true}
	return b.Dependencies()
}

// Name returns the human-friendly name of the asset.
func (a *BootstrapInPlace) Name() string {
	return "Bootstrap In Place Ignition Config"
}

// Files returns the password file.
func (a *BootstrapInPlace) Files() []*asset.File {
	if a.File != nil {
		return []*asset.File{a.File}
	}
	return []*asset.File{}
}

// Generate generates the ignition config for the Bootstrap asset.
func (a *BootstrapInPlace) Generate(dependencies asset.Parents) error {
	installConfig := &installconfig.InstallConfig{}
	dependencies.Get(installConfig)
	if err := verifyBootstrapInPlace(installConfig.Config); err != nil {
		return err
	}

	b := Bootstrap{BootstrapInPlace: true}
	b.Generate(dependencies)
	a.File = &asset.File{
		Filename: bootstrapInPlaceIgnFilename,
		Data:     b.File.Data,
	}
	return nil
}

// Load returns the bootstrap-in-place ignition from disk.
func (a *BootstrapInPlace) Load(f asset.FileFetcher) (found bool, err error) {
	file, err := f.FetchByName(bootstrapInPlaceIgnFilename)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}

	config := &igntypes.Config{}
	if err := json.Unmarshal(file.Data, config); err != nil {
		return false, errors.Wrapf(err, "failed to unmarshal %s", bootstrapIgnFilename)
	}

	a.File, a.Config = file, config
	warnIfCertificatesExpired(a.Config)
	return true, nil
}

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
	} else if installConfig.BootstrapInPlace.InstallationDisk == "" {
		errorList = append(errorList, field.Required(field.NewPath("bootstrapInPlace", "installationDisk"),
			"installationDisk must be set the target disk drive for the installation"))
	}
	return errorList.ToAggregate()
}
