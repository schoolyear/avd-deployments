package schema

import validation "github.com/go-ozzo/ozzo-validation/v4"

type ImageProperties struct {
	ImageName *string `json:"image_name"`
}

func (i ImageProperties) Validate() error {
	return validation.ValidateStruct(&i,
		validation.Field(&i.ImageName, validation.Required),
	)
}
