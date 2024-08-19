# How it works

All these files and folder structures all serve a single purpose: creating an image package.
This package is then used to start a Custom Image Template builder in AVD.

The package is assembled from multiple layers of folders into two files:

- a Custom Image Template spec that can be deployed to AVD
- a zipped resource folder that needs to be hosted such that the image builder can download it

A final deployment step performs the following actions:

- Upload resource folder to mirror
- Input the resource folder URL into the Custom Image Template spec
- Deploy the final spec to AVD in some way:
    - Automatically through the API
    - Output to disk such that it can be deployed manually

## How are image packages assembled?

Image packages are assembled by combining multiple layers of "package layers".
These layers are each described in their own folder structure that follows a specific structure.
Assembly is the act of merging these folder structures based on a specific rule set.

### Layer folder structure

- `properties.json(5)` (5 to allow for comments)
- resources
    - any files
- steps
    - `001_install.json(5)`
    - `002_finalize.json(5)`
    - etc.

The steps are all in the format of Customizer
Objects: https://learn.microsoft.com/en-us/azure/templates/microsoft.virtualmachineimages/imagetemplates?pivots=deployment-language-arm-template#imagetemplatecustomizer-objects-1

### Merging of layers

Each layer is merged using the following steps:

- `properties.json(5)`: add/overwrite lower layer
- resources: add together, on file/folder name collision, use the Layered Ordering algorithm, but only for files
  starting with `xxx_` (x being a digit).
- steps: add together using the Layered Ordering algorithm

### Layered Ordering algorithm

The Layered Ordering algorithm is meant to resolve file/folder name conflicts when merging layers.
These naming conflicts are common, because all layers use `000_` prefixes to describe the order of files.
This algorithm only works for files that start with `xxx_` prefixes (x=digit).

**Note**: since the Layered Ordering algorithm will change file names, do not reference these files by name.

Rules:

- On path collision
- Does the path base end with `xxx_*` (`x` is a digit)? If not, report collision failure
- Check path types
    - Both directories -> merge directories
    - One file, the other a directory -> report collision failure
    - Both a file -> continue
- Do the files have ordering preference (`000_pre_*` or `000_post_*`)? If so, resolve

## From image package to Custom Image Template

Based on the image building package, a Custom Image Template resource description can be generated:

- name: `app_name + git hash`
- identity: `[properties.json].avd.identity`
- build timeouts in minutes: `[properties.json].build_timeouts`
- customize:
    1. downloading of resources
    2. each steps `image_building_steps.json`
    3. delete the resources folder
- the rest: `[properties.json].avd.*`
    - distribute
    - vmProfile
    - validate
    - stagingResourceGroup

### Input folders

During VM image building, a collection a tree of files is downloaded.
In this folder structure, we expect a JSON file with AVD image building steps.
The folder structure is

Two inputs that get combined in an intelligent way.
The resulting folder is downloaded to a folder in the VM during image build.
The combining of the two folders can be done during image building, so the files can easily be hosted on Git.

- Base structure: `base/secure_apps_image`
- Image structure: `images/[some name]`

- Image building