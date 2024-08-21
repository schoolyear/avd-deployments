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
	Type string `json:"name"`
	// todo
}

func (b BuildStep) Validate() error {
	return validation.ValidateStruct(&b,
		validation.Field(&b.Type, validation.Required),
	)
}
