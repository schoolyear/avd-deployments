package lib

import (
	"encoding/json"
	"fmt"
	"github.com/friendsofgo/errors"
	"github.com/titanous/json5"
	"io/fs"
	"os"
)

// ReadJsonOrJson5File reads either the json or json5 file
// returns an error if both are found
// returns os.ErrNotExist if neither are found
func ReadJsonOrJson5File[T any](searchFs fs.FS, name string) (out *T, err error) {
	path, isJson5, err := findJsonOrJson5Path(searchFs, name)
	if err != nil {
		return nil, errors.Wrap(err, "failed to find either json or json5 path")
	}

	f, err := searchFs.Open(path)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to open file %s", path)
	}
	defer f.Close()

	if !isJson5 {
		if err := json.NewDecoder(f).Decode(&out); err != nil {
			return nil, errors.Wrap(err, "failed to parse json file")
		}
	} else {
		if err := json5.NewDecoder(f).Decode(&out); err != nil {
			return nil, errors.Wrap(err, "failed to parse json5 file")
		}
	}

	return out, nil
}

// findJsonOrJson5Path tries both the .json and .json5 extension
// returns an error if both are found
// returns os.ErrNotExist if neither are found
// returns the path and whether it is a json5 file on one is found
func findJsonOrJson5Path(searchFs fs.FS, name string) (path string, json5 bool, err error) {
	jsonPath := name + ".json"
	json5Path := name + ".json5"
	var jsonPathExists, json5PathExists bool

	jsonInfo, err := fs.Stat(searchFs, jsonPath)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return "", false, errors.Wrap(err, "failed to get info on json path")
		}
	} else {
		if jsonInfo.IsDir() {
			return "", false, fmt.Errorf("expected json file, but found directory %s", jsonPath)
		}

		jsonPathExists = true
	}

	json5Info, err := fs.Stat(searchFs, json5Path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return "", false, errors.Wrap(err, "failed to get info on json5 path")
		}
	} else {
		if json5Info.IsDir() {
			return "", false, fmt.Errorf("expected json5 file, but found directory %s", jsonPath)
		}

		json5PathExists = true
	}

	switch {
	case jsonPathExists && json5PathExists:
		return "", false, fmt.Errorf("both a json and a json5 file were found. choose one")
	case jsonPathExists:
		return jsonPath, false, nil
	case json5PathExists:
		return json5Path, true, nil
	default:
		return "", false, errors.Wrap(os.ErrNotExist, "neither json or json5 file was found")
	}
}
