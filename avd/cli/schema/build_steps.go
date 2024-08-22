package schema

import validation "github.com/go-ozzo/ozzo-validation/v4"

type BuildStepsConfig struct {
	Pre     []BuildStep `json:"pre"`
	Default []BuildStep `json:"default"`
	Post    []BuildStep `json:"post"`
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

type BuildStep struct {
	Type string `json:"type"`

	Sha256Checksum string   `json:"sha256Checksum,omitempty"` // File & PowerShell
	ScriptUri      string   `json:"scriptUri,omitempty"`      // PowerShell & Shell
	Inline         []string `json:"inline,omitempty"`         // PowerShell & Shell

	// File
	Destination string `json:"destination,omitempty"`
	SourceUri   string `json:"sourceUri,omitempty"`

	// PowerShell
	RunAsSystem    bool  `json:"runAsSystem,omitempty"`
	RunElevated    bool  `json:"runElevated,omitempty"`
	ValidExitCodes []int `json:"validExitCodes,omitempty"`

	// Shell
	// no unique fields

	// WindowsRestart
	RestartCheckCommand string `json:"restartCheckCommand,omitempty"`
	RestartCommand      string `json:"restartCommand,omitempty"`
	RestartTimeout      string `json:"restartTimeout,omitempty"`

	// WindowsUpdate
	Filters        []string `json:"filters,omitempty"`
	SearchCriteria string   `json:"searchCriteria,omitempty"`
	UpdateLimit    int      `json:"updateLimit,omitempty"`
}

func (b BuildStep) Validate() error {
	return validation.ValidateStruct(&b,
		validation.Field(&b.Type, validation.Required),
	)
}

// HardcodedBuildSteps returns the hardcoded build steps that get prefixed & postfixed to the configured build steps
func HardcodedBuildSteps(sha256Checksum string) (pre []BuildStep, post []BuildStep) {
	return []BuildStep{
			{
				Type:           "File",
				Destination:    "C:\\imagebuild_resources.zip",
				Sha256Checksum: sha256Checksum,
				SourceUri:      "[[[placeholder:sourceUri]]]",
			},
			{
				Type: "PowerShell",
				Inline: []string{
					"Expand-Archive -LiteralPath 'C:\\imagebuild_resources.zip' -DestinationPath 'C:\\imagebuild_resources'",
				},
				RunAsSystem: true,
				RunElevated: true,
			},
		}, []BuildStep{
			{
				Type: "PowerShell",
				Inline: []string{
					"Remove-Item -Path 'C:\\imagebuild_resources', 'C:\\imagebuild_resources.zip' -Recurse",
				},
				RunAsSystem: true,
				RunElevated: true,
			},
		}
}
