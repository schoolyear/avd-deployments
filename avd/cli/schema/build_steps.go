package schema

import (
	"encoding/json"
	"fmt"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/virtualmachineimagebuilder/armvirtualmachineimagebuilder"
	validation "github.com/go-ozzo/ozzo-validation/v4"
)

type BuildStepsConfig struct {
	Pre     BuildSteps `json:"pre"`
	Default BuildSteps `json:"default"`
	Post    BuildSteps `json:"post"`
}

func (b BuildStepsConfig) Validate() error {
	return validation.ValidateStruct(&b,
		validation.Field(&b.Pre),
		validation.Field(&b.Default),
		validation.Field(&b.Post),
	)
}

func (b BuildStepsConfig) TotalCount() int {
	return len(b.Pre) + len(b.Default) + len(b.Post)
}

type BuildSteps []BuildStep

func (b BuildSteps) ToCustomizerTypes() []armvirtualmachineimagebuilder.ImageTemplateCustomizerClassification {
	customizers := make([]armvirtualmachineimagebuilder.ImageTemplateCustomizerClassification, len(b))
	for i := range b {
		customizers[i] = b[i].V
	}
	return customizers
}

type BuildStep struct {
	V armvirtualmachineimagebuilder.ImageTemplateCustomizerClassification
}

func (b BuildStep) MarshalJSON() ([]byte, error) {
	return json.Marshal(b.V)
}

func (b *BuildStep) UnmarshalJSON(bytes []byte) error {
	var props armvirtualmachineimagebuilder.ImageTemplateProperties
	fullJSON := []byte(fmt.Sprintf(`{"customize": [%s]}`, bytes))
	if err := json.Unmarshal(fullJSON, &props); err != nil {
		return err
	}

	b.V = props.Customize[0]
	return nil
}

const SourceURIPlaceholder = "[[[deployment:sourceURI]]]"

// HardcodedBuildSteps returns the hardcoded build steps that get prefixed & postfixed to the configured build steps
func HardcodedBuildSteps(sha256Checksum string) (pre BuildSteps, post BuildSteps) {
	return BuildSteps{
			{V: &armvirtualmachineimagebuilder.ImageTemplateFileCustomizer{
				Type:           to.Ptr("File"),
				Destination:    to.Ptr("C:\\imagebuild_resources.zip"),
				Name:           to.Ptr("Download resources archive"),
				SHA256Checksum: to.Ptr(sha256Checksum),
				SourceURI:      to.Ptr(SourceURIPlaceholder),
			}},
			{V: &armvirtualmachineimagebuilder.ImageTemplatePowerShellCustomizer{
				Type:        to.Ptr("PowerShell"),
				Inline:      to.SliceOfPtrs(`Expand-Archive -LiteralPath 'C:\imagebuild_resources.zip' -DestinationPath 'C:\imagebuild_resources'`),
				Name:        to.Ptr("Extract resources archive"),
				RunAsSystem: to.Ptr(true),
				RunElevated: to.Ptr(true),
			}},
		}, BuildSteps{
			{V: &armvirtualmachineimagebuilder.ImageTemplatePowerShellCustomizer{
				Type:        to.Ptr("PowerShell"),
				Inline:      to.SliceOfPtrs(`Remove-Item -Path "C:\imagebuild_resources", "C:\imagebuild_resources.zip" -Recurse`),
				Name:        to.Ptr("Extract resources archive"),
				RunAsSystem: to.Ptr(true),
				RunElevated: to.Ptr(true),
			}},
			{V: &armvirtualmachineimagebuilder.ImageTemplatePowerShellCustomizer{
				Type:           to.Ptr("PowerShell"),
				Name:           to.Ptr("sysprep"),
				RunAsSystem:    to.Ptr(true),
				RunElevated:    to.Ptr(true),
				ScriptURI:      to.Ptr("https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/AdminSysPrep.ps1"),
				SHA256Checksum: to.Ptr("1dcaba4823f9963c9e51c5ce0adce5f546f65ef6034c364ef7325a0451bd9de9"),
			}},
		}
}
