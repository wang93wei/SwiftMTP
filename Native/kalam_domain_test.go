package main

import "testing"

func TestStorageIDValidate(t *testing.T) {
	tests := []struct {
		name    string
		id      StorageID
		wantErr bool
	}{
		{name: "zero is invalid", id: 0, wantErr: true},
		{name: "non-zero is valid", id: 1, wantErr: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.id.Validate()
			if (err != nil) != tt.wantErr {
				t.Fatalf("Validate() error = %v, wantErr = %v", err, tt.wantErr)
			}
		})
	}
}

func TestObjectIDValidate(t *testing.T) {
	tests := []struct {
		name    string
		id      ObjectID
		wantErr bool
	}{
		{name: "zero is invalid", id: 0, wantErr: true},
		{name: "non-zero is valid", id: 42, wantErr: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.id.Validate()
			if (err != nil) != tt.wantErr {
				t.Fatalf("Validate() error = %v, wantErr = %v", err, tt.wantErr)
			}
		})
	}
}

func TestParentIDValidate(t *testing.T) {
	tests := []struct {
		name    string
		id      ParentID
		wantErr bool
	}{
		{name: "zero is invalid", id: 0, wantErr: true},
		{name: "root is valid", id: ParentID(0xFFFFFFFF), wantErr: false},
		{name: "regular parent is valid", id: 99, wantErr: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.id.Validate()
			if (err != nil) != tt.wantErr {
				t.Fatalf("Validate() error = %v, wantErr = %v", err, tt.wantErr)
			}
		})
	}
}
