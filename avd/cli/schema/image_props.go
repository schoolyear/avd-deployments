package schema

import (
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/virtualmachineimagebuilder/armvirtualmachineimagebuilder"
	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/lib"
)

type ImageProperties struct {
	ImageTemplateName *string        `json:"imageTemplateName"`
	ImageTemplate     *ImageTemplate `json:"imageTemplate"`
}

func (i ImageProperties) Validate() error {
	return validation.ValidateStruct(&i,
		validation.Field(&i.ImageTemplateName, validation.Required),
		validation.Field(&i.ImageTemplate, validation.Required),
	)
}

type ImageTemplate struct {
	Identity   lib.Json5Unsupported[*armvirtualmachineimagebuilder.ImageTemplateIdentity]   `json:"identity"`
	Location   *string                                                                      `json:"location"`
	Properties lib.Json5Unsupported[*armvirtualmachineimagebuilder.ImageTemplateProperties] `json:"properties"`
	Tags       map[string]*string                                                           `json:"tags"`
}

func (i ImageTemplate) Validate() error {
	return validation.ValidateStruct(
		validation.Field(&i.Identity, validation.Required),
		validation.Field(&i.Location, validation.Required),
		validation.Field(&i.Properties, validation.Required),
		validation.Field(&i.Identity, validation.Required),
	)
}
