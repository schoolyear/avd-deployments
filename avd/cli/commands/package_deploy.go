package commands

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/virtualmachineimagebuilder/armvirtualmachineimagebuilder"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/friendsofgo/errors"
	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/schollz/progressbar/v3"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/schema"
	"github.com/urfave/cli/v2"
	"io"
	"io/fs"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
)

var PackageDeployCommand = &cli.Command{
	Name:  "deploy",
	Usage: "Deploy a package to Azure",
	Flags: []cli.Flag{
		&cli.StringFlag{
			Name:     "subscription",
			Required: true,
			Aliases:  []string{"s"},
		},
		&cli.StringFlag{
			Name:     "resource-group",
			Required: true,
			Aliases:  []string{"rg"},
		},
		&cli.PathFlag{
			Name:    "package",
			Value:   "./out",
			Usage:   "Path to the image building package",
			Aliases: []string{"p"},
		},
		&cli.PathFlag{
			Name:    "resources-uri",
			Usage:   "The URI path to which the resources archive can be uploaded. Required if the package contains a \"" + schema.SourceURIPlaceholder + "\" placeholder (almost always the case)",
			Aliases: []string{"r"},
		},
		&cli.StringFlag{
			Name:    "azure-tenant-id",
			Usage:   "Overwrite the default Azure Tenant ID",
			Aliases: []string{"atd"},
		},
		&cli.BoolFlag{
			Name:  "start",
			Usage: "Start image builder",
		},
		&cli.BoolFlag{
			Name:  "wait",
			Usage: "Wait for image builder to complete. Ignored if \"start\" flag is not set. This could take hours",
		},
		&cli.DurationFlag{
			Name:  "timeout",
			Usage: "Set after how much time the command should timeout. Especially useful in combination with \"-wait\"",
		},
	},
	Action: func(c *cli.Context) error {
		subscription := c.Path("subscription")
		resourceGroup := c.Path("resource-group")
		packagePath := c.Path("package")
		resourcesUriString := c.Path("resources-uri")
		azureTenantId := c.String("azure-tenant-id")
		startImageBuilderFlag := c.Bool("start")
		waitForImageCompletion := c.Bool("wait")
		timeoutFlag := c.Duration("timeout")

		var resourcesUri *storageAccountBlob
		if resourcesUriString != "" {
			var err error
			resourcesUri, err = parseResourcesURI(resourcesUriString)
			if err != nil {
				return errors.Wrap(err, "failed to parse resources-uri flag")
			}
		}

		ctx := context.Background()
		if timeoutFlag > 0 {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(context.Background(), timeoutFlag)
			defer cancel()
		}

		cwd, err := os.Getwd()
		if err != nil {
			return errors.Wrap(err, "failed to get current working directory")
		}
		fullPackagePath := filepath.Join(cwd, packagePath)

		packageFs := os.DirFS(packagePath)
		imageProperties, resourcesArchiveChecksum, err := scanPackagePath(packageFs)
		if err != nil {
			return errors.Wrapf(err, "failed to scan image package directory %s", fullPackagePath)
		}

		if err := validation.Validate(imageProperties); err != nil {
			return errors.Wrap(err, "invalid image properties file")
		}

		resourcesUri.Path = path.Join(resourcesUri.Path, fmt.Sprintf("%s-%x.zip", imageProperties.ImageTemplateName, resourcesArchiveChecksum))

		if err := replaceSourceURIPlaceholder(imageProperties.ImageTemplate.V, resourcesUri); err != nil {
			return errors.Wrap(err, "failed to replace resources URI placeholder")
		}

		azCred, err := azidentity.NewDefaultAzureCredential(&azidentity.DefaultAzureCredentialOptions{
			TenantID: azureTenantId,
		})
		if err != nil {
			return errors.Wrap(err, "failed to get default Azure Credentials")
		}

		if resourcesUri != nil {
			fmt.Println("Uploading resources archive")
			if err := uploadResourcesArchive(ctx, azCred, resourcesUri, packageFs, resourcesArchiveName); err != nil {
				return errors.Wrap(err, "failed to upload resources archive")
			}
			fmt.Println("Uploaded")
		}

		clientFactory, err := armvirtualmachineimagebuilder.NewClientFactory(subscription, azCred, nil)
		if err != nil {
			return errors.Wrap(err, "failed to initialize Azure SDK")
		}

		imageBuilderClient := clientFactory.NewVirtualMachineImageTemplatesClient()

		fmt.Println("Deploying image building template: " + imageProperties.ImageTemplateName)
		imageTemplateResourceId, err := createImageTemplate(ctx, imageBuilderClient, resourceGroup, imageProperties)
		if err != nil {
			return err
		}
		fmt.Println("Image Template created: ", imageTemplateResourceId)

		if startImageBuilderFlag {
			fmt.Println("Starting image builder")
			if err := startImageBuilder(context.Background(), imageBuilderClient, resourceGroup, imageProperties.ImageTemplateName, waitForImageCompletion); err != nil {
				return errors.Wrap(err, "failed to start image builder")
			}
		}

		return nil
	},
}

type storageAccountBlob struct {
	Service   string
	Container string
	Path      string
}

func (s storageAccountBlob) toURL() string {
	return fmt.Sprintf("%s/%s/%s", s.serviceURL(), s.Container, s.Path)
}

func (s storageAccountBlob) serviceURL() string {
	return fmt.Sprintf("https://%s", s.Service)
}

func parseResourcesURI(resourcesURI string) (*storageAccountBlob, error) {
	parsed, err := url.ParseRequestURI(resourcesURI)
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse as an URI")
	}

	pathParts := strings.SplitN(strings.TrimPrefix(parsed.Path, "/"), "/", 2)
	var blobPath string
	switch len(pathParts) {
	case 1:
		if len(strings.Trim(pathParts[0], "/")) == 0 {
			return nil, fmt.Errorf("expected at least container name to be included in URI path")
		}
	case 2:
		blobPath = pathParts[1]
	default:
		panic("programming error: no more than 2 entries expected")
	}
	if len(pathParts) != 2 {

	}

	return &storageAccountBlob{
		Service:   parsed.Host,
		Container: pathParts[0],
		Path:      blobPath,
	}, nil
}

func scanPackagePath(packageFs fs.FS) (imageProperties *schema.ImageProperties, archiveSha256 []byte, err error) {
	propertiesFile, err := packageFs.Open(imagePropertiesFileWithExtension)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to open properties file")
	}
	defer propertiesFile.Close()

	if err := json.NewDecoder(propertiesFile).Decode(&imageProperties); err != nil {
		return nil, nil, errors.Wrap(err, "failed to parse image properties json")
	}

	hash := sha256.New()
	resourcesFile, err := packageFs.Open(resourcesArchiveName)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to open resources archive")
	}
	defer resourcesFile.Close()

	resourcesFileStats, err := resourcesFile.Stat()
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to check for resources archive")
	}
	if resourcesFileStats.IsDir() {
		return nil, nil, errors.New("resources archive is expected to be a file, but it is a directory")
	}

	bar := progressbar.DefaultBytes(resourcesFileStats.Size(), "Calculating resources archive checksum")

	if _, err := io.Copy(io.MultiWriter(bar, hash), resourcesFile); err != nil {
		return nil, nil, errors.Wrap(err, "failed to calculate resources archive checksum")
	}

	return imageProperties, hash.Sum(nil), nil
}

func replaceSourceURIPlaceholder(imageTemplate *armvirtualmachineimagebuilder.ImageTemplate, resourcesURI *storageAccountBlob) error {
	var fileCustomizersWithPlaceholders []*armvirtualmachineimagebuilder.ImageTemplateFileCustomizer
	if imageTemplate.Properties != nil {
		for _, step := range imageTemplate.Properties.Customize {
			customizer := step.GetImageTemplateCustomizer()
			if customizer.Type != nil && *customizer.Type == "File" {
				fileCustomizer := step.(*armvirtualmachineimagebuilder.ImageTemplateFileCustomizer)
				if fileCustomizer.SourceURI != nil && *fileCustomizer.SourceURI == schema.SourceURIPlaceholder {
					fileCustomizersWithPlaceholders = append(fileCustomizersWithPlaceholders, fileCustomizer)
				}
			}
		}
	}
	if len(fileCustomizersWithPlaceholders) > 0 {
		if resourcesURI == nil {
			return fmt.Errorf(`resource-uri flag required, since package contains a "%s" placeholder`, schema.SourceURIPlaceholder)
		}

		for _, customizer := range fileCustomizersWithPlaceholders {
			customizer.SourceURI = to.Ptr(resourcesURI.toURL())
		}
	}

	return nil
}

func uploadResourcesArchive(ctx context.Context, azCreds azcore.TokenCredential, resourcesURI *storageAccountBlob, resourcesFs fs.FS, resourcesArchivePath string) error {
	resourcesFile, err := resourcesFs.Open(resourcesArchivePath)
	if err != nil {
		return errors.Wrap(err, "failed to open resources archive")
	}
	defer resourcesFile.Close()

	resourcesFileStat, err := resourcesFile.Stat()
	if err != nil {
		return errors.Wrap(err, "failed to check resource archive size")
	}

	blobClient, err := azblob.NewClient(resourcesURI.serviceURL(), azCreds, nil)
	if err != nil {
		return errors.Wrap(err, "failed to initialize Azure SDK")
	}

	bar := progressbar.DefaultBytes(resourcesFileStat.Size(), "Upload resources archive")
	defer bar.Exit()

	progressReader := progressbar.NewReader(resourcesFile, bar)
	defer progressReader.Close()

	_, err = blobClient.UploadStream(ctx, resourcesURI.Container, resourcesURI.Path, progressReader.Reader, nil)
	if err != nil {
		return errors.Wrap(err, "failed to upload")
	}

	bar.Finish()
	return nil
}

func createImageTemplate(ctx context.Context, imageTemplateClient *armvirtualmachineimagebuilder.VirtualMachineImageTemplatesClient, resourceGroup string, imageProperties *schema.ImageProperties) (string, error) {
	bar := progressbar.Default(-1, "Creating Image Template resource")
	createTemplatePoller, err := imageTemplateClient.BeginCreateOrUpdate(
		ctx,
		resourceGroup,
		imageProperties.ImageTemplateName,
		*imageProperties.ImageTemplate.V,
		nil,
	)
	if err != nil {
		return "", errors.Wrap(err, "failed to create Image Template")
	}

	createTemplateRes, err := createTemplatePoller.PollUntilDone(context.Background(), nil)
	bar.Finish()
	if err != nil {
		return "", errors.Wrap(err, "failed to wait until Image Template is created")
	}

	return *createTemplateRes.ID, nil
}

func startImageBuilder(ctx context.Context, imageTemplateClient *armvirtualmachineimagebuilder.VirtualMachineImageTemplatesClient, resourceGroup, name string, wait bool) error {
	poller, err := imageTemplateClient.BeginRun(ctx, resourceGroup, name, nil)
	if err != nil {
		return errors.Wrap(err, "failed to call beginRun api")
	}

	if wait {
		fmt.Println("Started Image Builder...this may take up to a few hours to finish")
		_, err := poller.PollUntilDone(ctx, nil)
		if err != nil {
			return errors.Wrap(err, "failed to poll until image builder is finished")
		}
		fmt.Println("Image Builder finished. Check the Azure Portal")
	} else {
		fmt.Println("Started image builder. You can track the progress in the Azure Portal")
	}

	return nil
}
