package schema

import (
	"encoding/json"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/virtualmachineimagebuilder/armvirtualmachineimagebuilder"
	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/lib"
	"regexp"
)

type ImageProperties struct {
	PlaceholderProperties PlaceholderProperties                                              `json:"placeholderProperties"`
	ImageTemplate         lib.Json5Unsupported[*armvirtualmachineimagebuilder.ImageTemplate] `json:"imageTemplate"`
}

func (i ImageProperties) Validate() error {
	return validation.ValidateStruct(&i,
		validation.Field(&i.PlaceholderProperties, validation.Length(0, 50)),
		validation.Field(&i.ImageTemplate, validation.Required),
	)
}

type PlaceholderProperties map[string]json.RawMessage

type PlaceholderType string

const (
	PropertiesPlaceholder PlaceholderType = "props"
	ParameterPlaceholder  PlaceholderType = "param"
)

var placeholderRegex = regexp.MustCompile(`\[{3}([a-zA-Z0-9_]+):([a-zA-Z0-9_]+)]{3}`)

func FindPlaceholdersInJson(bytes []byte, placeholderType PlaceholderType) map[string]struct{} {
	matchIndexes := placeholderRegex.FindAllSubmatchIndex(bytes, -1)
	matches := make(map[string]struct{}, len(matchIndexes))
	for _, match := range matchIndexes {
		pType := string(bytes[match[2]:match[3]])
		if pType == string(placeholderType) {
			key := string(bytes[match[4]:match[5]])
			matches[key] = struct{}{}
		}
	}

	return matches
}

func ReplacePlaceholders(bytes []byte, mapping map[string]string, placeholderType PlaceholderType) []byte {
	return placeholderRegex.ReplaceAllFunc(bytes, func(bytes []byte) []byte {
		match := placeholderRegex.FindSubmatch(bytes)
		if string(match[1]) != string(placeholderType) {
			return bytes
		}
		return []byte(mapping[string(match[2])])
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
