package schema

import (
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/virtualmachineimagebuilder/armvirtualmachineimagebuilder"
	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/lib"
	"regexp"
)

type ImageProperties struct {
	ImageTemplate lib.Json5Unsupported[*armvirtualmachineimagebuilder.ImageTemplate] `json:"imageTemplate"`
}

func (i ImageProperties) Validate() error {
	return validation.ValidateStruct(&i,
		validation.Field(&i.ImageTemplate, validation.Required),
	)
}

var paramRegex = regexp.MustCompile(`\[{3}(param):([a-zA-Z0-9_]+)]{3}`)

func FindParametersInPropertiesJson(propertiesJson []byte) map[string]struct{} {
	matchIndexes := paramRegex.FindAllSubmatchIndex(propertiesJson, -1)
	matches := make(map[string]struct{}, len(matchIndexes))
	for _, match := range matchIndexes {
		key := string(propertiesJson[match[4]:match[5]])
		matches[key] = struct{}{}
	}

	return matches
}

func ReplaceParametersInPropertiesJson(propertiesJson []byte, resolvedParams map[string]string) []byte {
	return paramRegex.ReplaceAllFunc(propertiesJson, func(bytes []byte) []byte {
		match := paramRegex.FindSubmatch(bytes)
		return []byte(resolvedParams[string(match[2])])
	})
}

// SetBuildSteps sets the customizer steps for the image template.
// returns true if some customizer steps are already set (meaning the new steps are not added)
func (i ImageProperties) SetBuildSteps(buildSteps []armvirtualmachineimagebuilder.ImageTemplateCustomizerClassification) (conflict bool) {
	if i.ImageTemplate.V.Properties == nil {
		i.ImageTemplate.V.Properties = &armvirtualmachineimagebuilder.ImageTemplateProperties{}
	} else if len(i.ImageTemplate.V.Properties.Customize) > 0 {
		return true
	}

	i.ImageTemplate.V.Properties.Customize = buildSteps
	return false
}

// HardcodedImageTemplateTag is a magic tag in Azure that makes vm image templates show up in the AVD console
const HardcodedImageTemplateTag = "AVD_IMAGE_TEMPLATE"
