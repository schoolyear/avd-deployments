package lib

import (
	"reflect"
	"testing"
)

func Test_normalizeEntryName(t *testing.T) {
	type args struct {
		name  string
		isDir bool
	}
	tests := []struct {
		name           string
		args           args
		wantNormalized normalizedEntryName
		wantTargetName string
		wantIndex      int
		wantPreference orderingType
	}{
		{"empty", args{"", false}, normalizedEntryName{false, ""}, "", 0, unordered},
		{"normal file", args{"file.txt", false}, normalizedEntryName{false, "file.txt"}, "file.txt", 0, unordered},
		{"ordered file", args{"020_file.txt", false}, normalizedEntryName{true, ""}, "file.txt", 20, ordered},
		{"pre ordered file", args{"020_pre_file.txt", false}, normalizedEntryName{true, ""}, "file.txt", 20, preOrderingPreference},
		{"post ordered file", args{"020_post_file.txt", false}, normalizedEntryName{true, ""}, "file.txt", 20, postOrderingPreference},
		{"directory", args{"testdir", true}, normalizedEntryName{false, "testdir"}, "testdir", 0, unordered},
		{"directory with ordering", args{"000_testdir", true}, normalizedEntryName{false, "000_testdir"}, "000_testdir", 0, unordered},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotNormalized, gotTargetName, gotIndex, gotPreference := normalizeEntryName(tt.args.name, tt.args.isDir)
			if !reflect.DeepEqual(gotNormalized, tt.wantNormalized) {
				t.Errorf("normalizeEntryName() gotNormalized = %+v, want %+v", gotNormalized, tt.wantNormalized)
			}
			if gotTargetName != tt.wantTargetName {
				t.Errorf("normalizeEntryName() gotTargetName = %v, want %v", gotTargetName, tt.wantTargetName)
			}
			if gotIndex != tt.wantIndex {
				t.Errorf("normalizeEntryName() gotIndex = %v, want %v", gotIndex, tt.wantIndex)
			}
			if gotPreference != tt.wantPreference {
				t.Errorf("normalizeEntryName() gotPreference = %v, want %v", gotPreference, tt.wantPreference)
			}
		})
	}
}
