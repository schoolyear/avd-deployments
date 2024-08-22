package commands

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	jsonpatch "github.com/evanphx/json-patch/v5"
	"github.com/friendsofgo/errors"
	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/inhies/go-bytesize"
	"github.com/schollz/progressbar/v3"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/lib"
	"github.com/schoolyear/secure-apps-scripts/avd/cli/schema"
	"github.com/urfave/cli/v2"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
)

var ImageBuildCommand = &cli.Command{
	Name:  "build",
	Usage: "Build image package",
	Flags: []cli.Flag{
		&cli.StringSliceFlag{
			Name:        "layer",
			Category:    "",
			DefaultText: "",
			FilePath:    "",
			Usage:       "Paths to the image layers",
			Required:    true,
			TakesFile:   true,
			Aliases:     []string{"l"},
		},
		&cli.PathFlag{
			Name:    "output",
			Usage:   "Path to which the image package will be written",
			Value:   "./out",
			Aliases: []string{"o"},
		},
		&cli.BoolFlag{
			Name:  "dry-run",
			Usage: "Don't actually copy files",
		},
		&cli.BoolFlag{
			Name:  "overwrite-output",
			Usage: "Overwrite the output directory",
		},
	},
	Action: func(c *cli.Context) error {
		layerPaths := c.StringSlice("layer")
		outputPath := c.Path("output")
		dryRun := c.Bool("dry-run")
		overwriteOutput := c.Bool("overwrite-output")

		cwd, err := os.Getwd()
		if err != nil {
			return errors.Wrap(err, "failed to get current working directory")
		}

		layerPaths, err = resolveAbsoluteLayerPaths(cwd, layerPaths)
		if err != nil {
			return errors.Wrap(err, "failed to convert layer paths to absolute paths")
		}

		if err := ensureLayerPathsExist(layerPaths); err != nil {
			return err
		}

		// check each layer
		layers := make([]layerProps, len(layerPaths))
		for i, layerPath := range layerPaths {
			layerFs := os.DirFS(layerPath)
			scanResult, err := scanLayerPath(layerFs)
			if err != nil {
				return errors.Wrapf(err, "failed to scan layer %d: %s", i+1, layerPath)
			}

			var resourcesFs fs.FS
			if scanResult.hasResourcesFolder {
				var err error
				resourcesFs, err = fs.Sub(layerFs, resourcesDirName)
				if err != nil {
					return errors.Wrapf(err, "failed to create resources filesystem for layer %d", i+1)
				}
			} else {
				resourcesFs = lib.EmptyFs{}
			}

			layers[i] = layerProps{
				basePath:        layerPath,
				fsys:            layerFs,
				resourcesFs:     resourcesFs,
				layerScanResult: scanResult,
			}
		}

		if err := printLayers(layers); err != nil {
			return errors.Wrap(err, "failed to print layers")
		}

		fmt.Println("Merging image properties")
		imageProperties, err := mergeImageProperties(layers)
		if err != nil {
			return errors.Wrap(err, "failed to merge image property documents")
		}

		niceImagePropsJson, err := json.MarshalIndent(imageProperties, "", "\t")
		if err != nil {
			return errors.Wrap(err, "failed to nicely print image properties")
		}

		if err := validation.Validate(imageProperties); err != nil {
			fmt.Printf("Image Properties:\n%s\n", niceImagePropsJson)
			return errors.Wrap(err, "merged image properties result in an invalid document")
		}

		fmt.Println("Merging build steps")
		buildSteps := mergeBuildStepConfigs(layers)
		niceBuildStepsJson, err := json.MarshalIndent(buildSteps, "", "\t")
		if err != nil {
			return errors.Wrap(err, "failed to nicely print build steps config")
		}

		if err := validation.Validate(buildSteps); err != nil {
			fmt.Printf("Build steps:\n%s\n", niceBuildStepsJson)
			return errors.Wrap(err, "merged build steps configs result in an invalid document")
		}

		fmt.Println("Merging resources folders")
		resourceFileMappings, err := mergeResourcesDir(layers)
		if err != nil {
			return errors.Wrap(err, "failed to merge resources directories")
		}

		fmt.Println("Merging complete")

		fmt.Println("The following ordered resource files will be renamed:")
		renamed := 0
		for i := range layers {
			for _, fileMapping := range resourceFileMappings {
				if fileMapping.LayerIdx == i && fileMapping.SourcePath != fileMapping.TargetPath { // efficient enough for low number of layers
					fmt.Printf("\t(layer %d) %s -> %s\n", i+1, fileMapping.SourcePath, filepath.Base(fileMapping.TargetPath))
					renamed++
				}
			}
		}
		if renamed == 0 {
			fmt.Println("\tNo files will be renamed")
		}
		fmt.Println()

		if dryRun {
			fmt.Println("Dry run: not writing the image building package")
			return nil
		}

		fmt.Println("Writing the image building package")
		fullOutputPath := filepath.Join(cwd, outputPath)
		if err := writeImageBuildingPackage(fullOutputPath, layers, imageProperties, buildSteps, resourceFileMappings, overwriteOutput); err != nil {
			return errors.Wrap(err, "failed to write image building package")
		}

		fmt.Printf("Package written to %s\n", fullOutputPath)

		return nil
	},
}

type layerProps struct {
	basePath    string
	fsys        fs.FS
	resourcesFs fs.FS
	layerScanResult
}

type layerScanResult struct {
	properties         *schema.ImageProperties
	buildStepsConfig   *schema.BuildStepsConfig
	hasResourcesFolder bool
	resourcesSize      int64 // 0, if hasResourcesFolder = false
}

const (
	imagePropertiesFilename = "properties"
	buildStepsFileName      = "build_steps"
	resourcesDirName        = "resources"
)

func resolveAbsoluteLayerPaths(cwd string, layerPaths []string) ([]string, error) {
	fullPaths := make([]string, len(layerPaths))
	for i, layerPath := range layerPaths {
		var fullPath string
		if filepath.IsAbs(layerPath) {
			fullPath = layerPath
		} else {
			fullPath = filepath.Join(cwd, layerPath)
		}
		fullPaths[i] = fullPath
	}
	return fullPaths, nil
}

func ensureLayerPathsExist(layerPaths []string) error {
	for _, layerPath := range layerPaths {
		fileInfo, err := os.Stat(layerPath)
		if err != nil {
			return errors.Wrap(err, "failed to check layer path exists")
		}

		if !fileInfo.IsDir() {
			return fmt.Errorf("layer path does not point to a directory: %s", layerPath)
		}
	}

	return nil
}

func scanLayerPath(layerFs fs.FS) (layer layerScanResult, err error) {
	props, err := lib.ReadJsonOrJson5File[schema.ImageProperties](layerFs, imagePropertiesFilename)
	if err != nil && !errors.Is(err, os.ErrNotExist) { // ok if the file does not exist
		return layer, errors.Wrap(err, "failed to read properties file")
	}
	layer.properties = props

	buildSteps, err := lib.ReadJsonOrJson5File[schema.BuildStepsConfig](layerFs, buildStepsFileName)
	if err != nil && !errors.Is(err, os.ErrNotExist) { // ok if the file does not exist
		return layer, errors.Wrap(err, "failed to read build_steps file")
	}
	layer.buildStepsConfig = buildSteps

	resourcesInfo, err := fs.Stat(layerFs, resourcesDirName)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return layer, errors.Wrap(err, "failed to get info on resources folder")
		}
	} else if !resourcesInfo.IsDir() {
		return layer, errors.New(`expected "resources" to be a folder, it isn't'`)
	} else {
		layer.hasResourcesFolder = true
		resourcesFs, err := fs.Sub(layerFs, resourcesDirName)
		if err != nil {
			return layer, errors.Wrap(err, "failed to create sub-filesystem for resources folder")
		}

		layer.resourcesSize, err = lib.CalcDirSizeRecursively(resourcesFs)
		if err != nil {
			return layer, errors.Wrap(err, "failed to calculate size of resource directory")
		}
	}

	return layer, nil
}

func printLayers(layers []layerProps) error {
	fmt.Println("Merging the following layers")
	for i, layer := range layers {
		buildStepsCount := "not configured"
		if layer.buildStepsConfig != nil {
			buildStepsCount = strconv.Itoa(layer.buildStepsConfig.TotalCount())
		}

		resourcesSize := "no resource folder"
		if layer.hasResourcesFolder {
			resourcesSize = bytesize.New(float64(layer.resourcesSize)).String()
		}

		fmt.Printf("\t(%d) %s\n\t\thas properties: %v, build_steps: %s, resources: %s\n",
			i+1,
			layer.basePath,
			layer.properties != nil,
			buildStepsCount,
			resourcesSize,
		)
	}
	fmt.Println()

	return nil
}

func mergeImageProperties(layers []layerProps) (*schema.ImageProperties, error) {
	var propsJson []byte
	for i, layer := range layers {
		if layer.properties == nil {
			continue
		}
		layerPropsJson, err := json.Marshal(layer.properties)
		if err != nil {
			return nil, errors.Wrapf(err, "failed to marshal properties of layer %d", i+1)
		}

		if i == 0 {
			propsJson = layerPropsJson
		} else {
			propsJson, err = jsonpatch.MergePatch(propsJson, layerPropsJson)
			if err != nil {
				return nil, errors.Wrapf(err, "failed to merge properties of layer %d", i+1)
			}
		}
	}

	var props schema.ImageProperties
	if err := json.Unmarshal(propsJson, &props); err != nil {
		return nil, errors.Wrap(err, "failed to marshal patched json document")
	}

	return &props, nil
}

func mergeBuildStepConfigs(layers []layerProps) []schema.BuildStep {
	buildStepsConfig := schema.BuildStepsConfig{
		Pre:     []schema.BuildStep{},
		Default: []schema.BuildStep{},
		Post:    []schema.BuildStep{},
	}
	for _, layer := range layers {
		if layer.buildStepsConfig == nil {
			continue
		}
		buildStepsConfig.Pre = append(buildStepsConfig.Pre, layer.buildStepsConfig.Pre...)
		buildStepsConfig.Default = append(buildStepsConfig.Default, layer.buildStepsConfig.Default...)
		buildStepsConfig.Post = append(buildStepsConfig.Post, layer.buildStepsConfig.Post...)
	}

	var buildSteps []schema.BuildStep
	buildSteps = append(buildSteps, buildStepsConfig.Pre...)
	buildSteps = append(buildSteps, buildStepsConfig.Default...)
	buildSteps = append(buildSteps, buildStepsConfig.Post...)

	return buildSteps
}

func mergeResourcesDir(layers []layerProps) ([]lib.FileMapping, error) {
	layerFSs := make([]fs.FS, len(layers))
	for i, layer := range layers {
		layerFSs[i] = layer.resourcesFs
	}

	fileMappings, fileCollisions, pathTypeCollisions, err := lib.MergeDirectoryLayers(layerFSs, ".")
	if err != nil {
		return nil, errors.Wrap(err, "failed to merge layer directories")
	}

	if len(fileCollisions) > 0 || len(pathTypeCollisions) > 0 {
		if len(fileCollisions) > 0 {
			fmt.Println("The following path(s) have colliding files:")
			for _, collision := range fileCollisions {
				fmt.Printf("- %s\n", collision.Path)
				for _, layerIdx := range collision.CollidingLayerIndexes {
					fmt.Printf("\t+(%d): %s\n", layerIdx, layers[layerIdx].basePath)
				}
			}
		}

		if len(pathTypeCollisions) > 0 {
			fmt.Println("On the following path(s) both files and directories exist with the same name:")
			for _, collision := range pathTypeCollisions {
				fmt.Printf("- %s\n", collision.Path)
				for _, layerIdx := range collision.DirectoryLayerIndexes {
					fmt.Printf("\t[DIR ](%d): %s\n", layerIdx, filepath.Join(layers[layerIdx].basePath, collision.Path))
				}
				for _, layerIdx := range collision.FileLayerIndexes {
					fmt.Printf("\t[DIR ](%d): %s\n", layerIdx, filepath.Join(layers[layerIdx].basePath, collision.Path))
				}
			}
		}

		return nil, errors.New("unable to merge layers")
	}

	return fileMappings, nil
}

func writeImageBuildingPackage(outputPath string, layers []layerProps, imageProperties *schema.ImageProperties, buildSteps []schema.BuildStep, resourceFileMappings []lib.FileMapping, overwriteOutputDir bool) error {
	if err := lib.EnsureEmptyDirectory(outputPath, overwriteOutputDir); err != nil {
		return errors.Wrap(err, "failed to create output directory")
	}

	imagePropertiesJson, err := json.MarshalIndent(imageProperties, "", "\t")
	if err != nil {
		return errors.Wrap(err, "failed to json marshal image properties")
	}

	// we don't know the length of the build steps json yet, so we do an estimation
	const buildStepsJsonEstimate = 1000
	bar := progressbar.DefaultBytes(
		int64(len(imagePropertiesJson))+int64(buildStepsJsonEstimate)+calcFileMappingsTotalSize(resourceFileMappings),
		"Creating resources archive",
	)

	imagePropertiesPath := filepath.Join(outputPath, imagePropertiesFilename+".json")
	if err := createAndWriteFile(imagePropertiesPath, imagePropertiesJson, bar); err != nil {
		return errors.Wrapf(err, "failed to write image properties file to %s", imagePropertiesPath)
	}

	resourcesArchivePath := filepath.Join(outputPath, resourcesDirName+".zip")
	resourcesSha256Checksum, err := writeResourcesArchive(resourcesArchivePath, layers, resourceFileMappings, bar)
	if err != nil {
		return errors.Wrapf(err, "failed to write resources archive to %s", resourcesArchivePath)
	}

	resourcesSha256ChecksumHex := hex.EncodeToString(resourcesSha256Checksum)
	preSteps, postSteps := schema.HardcodedBuildSteps(resourcesSha256ChecksumHex)
	buildSteps = append(preSteps, buildSteps...)
	buildSteps = append(buildSteps, postSteps...)

	buildStepsJson, err := json.MarshalIndent(buildSteps, "", "\t")
	if err != nil {
		return errors.Wrap(err, "failed to json marshal build steps")
	}

	bar.ChangeMax(bar.GetMax() - buildStepsJsonEstimate + len(buildStepsJson)) // replace estimate with actual byte size
	buildStepsPath := filepath.Join(outputPath, buildStepsFileName+".json")
	if err := createAndWriteFile(buildStepsPath, buildStepsJson, bar); err != nil {
		return errors.Wrapf(err, "failed to write build steps file to %s", imagePropertiesPath)
	}

	bar.Finish()
	bar.Exit()

	return nil
}

func createAndWriteFile(path string, data []byte, bar *progressbar.ProgressBar) error {
	bar.Describe(filepath.Base(path))
	f, err := os.Create(path)
	if err != nil {
		return errors.Wrap(err, "failed to create file")
	}
	defer f.Close()

	_, err = io.Copy(io.MultiWriter(f, bar), bytes.NewReader(data))
	return errors.Wrap(err, "failed to write file")
}

func writeResourcesArchive(archivePath string, layers []layerProps, fileMappings []lib.FileMapping, bar *progressbar.ProgressBar) (sha256Checksum []byte, err error) {
	archiveFile, err := os.Create(archivePath)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create zip file")
	}
	defer archiveFile.Close()

	hash := sha256.New()
	archiveWriter := io.MultiWriter(archiveFile, hash)
	archive := zip.NewWriter(archiveWriter)

	for _, mapping := range fileMappings {
		bar.Describe(mapping.TargetPath)
		if err := addFileToResourcesArchive(layers[mapping.LayerIdx].resourcesFs, mapping, archive, bar); err != nil {
			return nil, errors.Wrapf(err, "failed to add file to resources archive: %s", mapping.TargetPath)
		}
	}

	bar.Describe("Writing archive")
	if err := archive.Close(); err != nil {
		return nil, errors.Wrap(err, "failed to finalize zip file")
	}

	return hash.Sum(nil), nil
}

func calcFileMappingsTotalSize(mappings []lib.FileMapping) (total int64) {
	for _, mapping := range mappings {
		total += mapping.Size
	}
	return
}

func addFileToResourcesArchive(sourceFs fs.FS, fileMapping lib.FileMapping, archive *zip.Writer, secondaryWriter io.Writer) error {
	sourceFile, err := sourceFs.Open(fileMapping.SourcePath)
	if err != nil {
		return errors.Wrap(err, "failed to open source file")
	}
	defer sourceFile.Close()

	header := zip.FileHeader{
		Name:               fileMapping.TargetPath,
		Comment:            fmt.Sprintf("from layer %d: %s", fileMapping.LayerIdx+1, fileMapping.SourcePath),
		Modified:           fileMapping.Modified,
		UncompressedSize64: uint64(fileMapping.Size),
	}
	header.SetMode(fileMapping.FileMode)
	archiveFile, err := archive.CreateHeader(&header)
	if err != nil {
		return errors.Wrap(err, "failed to create file in archive")
	}

	_, err = io.Copy(io.MultiWriter(archiveFile, secondaryWriter), sourceFile)
	return errors.Wrap(err, "failed to copy file to archive")
}
