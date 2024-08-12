package embeddedfiles

import "embed"

//go:embed image_template/*
var ImageTemplate embed.FS

const ImageTemplateBasePath = "image_template"
