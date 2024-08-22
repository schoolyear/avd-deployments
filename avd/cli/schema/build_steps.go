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
	fullJson := []byte(fmt.Sprintf(`{"customize": [%s]}`, bytes))
	if err := json.Unmarshal(fullJson, &props); err != nil {
		return err
	}

	b.V = props.Customize[0]
	return nil
}

//
//type BuildStep struct {
//	Type string `json:"type"`
//
//	Sha256Checksum string   `json:"sha256Checksum,omitempty"` // File & PowerShell
//	ScriptUri      string   `json:"scriptUri,omitempty"`      // PowerShell & Shell
//	Inline         []string `json:"inline,omitempty"`         // PowerShell & Shell
//
//	// File
//	Destination string `json:"destination,omitempty"`
//	SourceUri   string `json:"sourceUri,omitempty"`
//
//	// PowerShell
//	RunAsSystem    bool  `json:"runAsSystem,omitempty"`
//	RunElevated    bool  `json:"runElevated,omitempty"`
//	ValidExitCodes []int `json:"validExitCodes,omitempty"`
//
//	// Shell
//	// no unique fields
//
//	// WindowsRestart
//	RestartCheckCommand string `json:"restartCheckCommand,omitempty"`
//	RestartCommand      string `json:"restartCommand,omitempty"`
//	RestartTimeout      string `json:"restartTimeout,omitempty"`
//
//	// WindowsUpdate
//	Filters        []string `json:"filters,omitempty"`
//	SearchCriteria string   `json:"searchCriteria,omitempty"`
//	UpdateLimit    int      `json:"updateLimit,omitempty"`
//}
//
//func (b BuildStep) Validate() error {
//	return validation.ValidateStruct(&b,
//		validation.Field(&b.Type, validation.Required),
//	)
//}
//

// HardcodedBuildSteps returns the hardcoded build steps that get prefixed & postfixed to the configured build steps
func HardcodedBuildSteps(sha256Checksum string) (pre BuildSteps, post BuildSteps) {
	return BuildSteps{
			{V: &armvirtualmachineimagebuilder.ImageTemplateFileCustomizer{
				Type:           to.Ptr("File"),
				Destination:    to.Ptr("C:\\imagebuild_resources.zip"),
				Name:           to.Ptr("Download resources archive"),
				SHA256Checksum: to.Ptr(sha256Checksum),
				SourceURI:      to.Ptr("[[[placeholder:sourceUri]]]"),
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
				Inline:      to.SliceOfPtrs(`Remove-Item -Path 'C:\imagebuild_resources', 'C:\imagebuild_resources.zip' -Recurse`),
				Name:        to.Ptr("Extract resources archive"),
				RunAsSystem: to.Ptr(true),
				RunElevated: to.Ptr(true),
			}},
		}
}
