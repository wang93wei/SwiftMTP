package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/ganeshrvel/go-mtpfs/mtp"
)

// fixtureJSON 是 Go 与 Swift 共享的黄金契约载体。
// hex = 线协议字节; expected = 期望解码出的字段(JSON 中立表示)。
type fixtureJSON struct {
	Name     string          `json:"name"`
	Hex      string          `json:"hex"`
	Expected json.RawMessage `json:"expected"`
}

// fixtureDir 指向 MTPCore 的 Fixtures 目录(go test 在 Native/ 跑,相对路径可达)。
func fixtureDir(t *testing.T) string {
	dir := filepath.Join("..", "Packages", "MTPCore", "Tests", "MTPCoreTests", "Fixtures")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir fixtures: %v", err)
	}
	return dir
}

func writeFixture(t *testing.T, name string, value any, encoded []byte) {
	t.Helper()
	exp, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal expected: %v", err)
	}
	fx := fixtureJSON{Name: name, Hex: hex.EncodeToString(encoded), Expected: exp}
	b, err := json.MarshalIndent(fx, "", "  ")
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	path := filepath.Join(fixtureDir(t), name+".json")
	if err := os.WriteFile(path, b, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	t.Logf("生成 fixture: %s (%d bytes hex)", path, len(encoded))
}

// TestGenerateFixtures 用 mtp.Encode 把已知结构体编码成线协议字节,落 JSON fixture。
// 这些 fixture 是 Go 与 Swift 共享的黄金契约真理源。
func TestGenerateFixtures(t *testing.T) {
	// 1. ObjectInfo(代表一个普通文件)
	obj := mtp.ObjectInfo{
		StorageID:      0x00010001,
		ObjectFormat:   0x3000, // Undefined(普通文件)
		CompressedSize: 100,
		ParentObject:   0xFFFFFFFF,
		Filename:       "test.txt",
		// CaptureDate/ModificationDate 留 zero(编码为空字符串)
	}
	var buf bytes.Buffer
	if err := mtp.Encode(&buf, &obj); err != nil {
		t.Fatalf("encode ObjectInfo: %v", err)
	}
	type objectInfoExpected struct {
		StorageID      uint32 `json:"storageID"`
		ObjectFormat   uint16 `json:"objectFormat"`
		CompressedSize uint32 `json:"compressedSize"`
		ParentObject   uint32 `json:"parentObject"`
		Filename       string `json:"filename"`
	}
	writeFixture(t, "objectinfo_simple", objectInfoExpected{
		StorageID: obj.StorageID, ObjectFormat: obj.ObjectFormat,
		CompressedSize: obj.CompressedSize, ParentObject: obj.ParentObject,
		Filename: obj.Filename,
	}, buf.Bytes())

	// 2. ObjectInfo 带时间(验证三星尾点兼容:Go Encode 输出标准格式,decode 三变体另测)
	obj2 := mtp.ObjectInfo{
		StorageID:        0x00010001,
		CompressedSize:   4096,
		ParentObject:     0xFFFFFFFF,
		Filename:         "照片.jpg", // 验证非 ASCII / CJK
		ModificationDate: time.Date(2026, 6, 13, 14, 30, 0, 0, time.UTC),
	}
	buf.Reset()
	if err := mtp.Encode(&buf, &obj2); err != nil {
		t.Fatalf("encode ObjectInfo2: %v", err)
	}
	type objectInfoCJKExpected struct {
		Filename         string  `json:"filename"`
		CompressedSize   uint32  `json:"compressedSize"`
		ModificationTime float64 `json:"modificationTime"` // Unix 秒;0 表示无时间
	}
	writeFixture(t, "objectinfo_cjk", objectInfoCJKExpected{
		Filename: obj2.Filename, CompressedSize: obj2.CompressedSize,
		ModificationTime: float64(obj2.ModificationDate.Unix()),
	}, buf.Bytes())

	// 3. StorageInfo
	st := mtp.StorageInfo{
		StorageType:        0x0003, // ST_RemovableRAM
		FilesystemType:     0x0002, // FST_GenericHierarchical
		MaxCapability:      64 * 1024 * 1024 * 1024, // 64GB
		FreeSpaceInBytes:   32 * 1024 * 1024 * 1024, // 32GB
		StorageDescription: "Internal shared storage",
		VolumeLabel:        "Phone",
	}
	buf.Reset()
	if err := mtp.Encode(&buf, &st); err != nil {
		t.Fatalf("encode StorageInfo: %v", err)
	}
	type storageInfoExpected struct {
		StorageType        uint16 `json:"storageType"`
		FilesystemType     uint16 `json:"filesystemType"`
		MaxCapability      uint64 `json:"maxCapability"`
		FreeSpaceInBytes   uint64 `json:"freeSpaceInBytes"`
		StorageDescription string `json:"storageDescription"`
		VolumeLabel        string `json:"volumeLabel"`
	}
	writeFixture(t, "storageinfo_simple", storageInfoExpected{
		StorageType: st.StorageType, FilesystemType: st.FilesystemType,
		MaxCapability: st.MaxCapability, FreeSpaceInBytes: st.FreeSpaceInBytes,
		StorageDescription: st.StorageDescription, VolumeLabel: st.VolumeLabel,
	}, buf.Bytes())

	// 4. Uint32Array(GetObjectHandles 返回形态)
	arr := mtp.Uint32Array{Values: []uint32{0x00000001, 0x00000002, 0x00000003}}
	buf.Reset()
	if err := mtp.Encode(&buf, &arr); err != nil {
		t.Fatalf("encode Uint32Array: %v", err)
	}
	type uint32ArrayExpected struct {
		Values []uint32 `json:"values"`
	}
	writeFixture(t, "uint32array_simple", uint32ArrayExpected{Values: arr.Values}, buf.Bytes())

	// 5. DeviceInfo(精简:仅必填字段,数组/字符串混合)
	di := mtp.DeviceInfo{
		StandardVersion:      100,
		MTPVendorExtensionID: 0x00000006,
		MTPVersion:           100,
		MTPExtension:         "microsoft.com: 1.0;",
		Manufacturer:         "Google",
		Model:                "Pixel 8",
		DeviceVersion:        "1.0",
		SerialNumber:         "SERIAL123",
	}
	buf.Reset()
	if err := mtp.Encode(&buf, &di); err != nil {
		t.Fatalf("encode DeviceInfo: %v", err)
	}
	type deviceInfoExpected struct {
		StandardVersion      uint16 `json:"standardVersion"`
		MTPVendorExtensionID uint32 `json:"mtpVendorExtensionID"`
		Manufacturer         string `json:"manufacturer"`
		Model                string `json:"model"`
		SerialNumber         string `json:"serialNumber"`
	}
	writeFixture(t, "deviceinfo_simple", deviceInfoExpected{
		StandardVersion: di.StandardVersion, MTPVendorExtensionID: di.MTPVendorExtensionID,
		Manufacturer: di.Manufacturer, Model: di.Model, SerialNumber: di.SerialNumber,
	}, buf.Bytes())

	fmt.Println("黄金 fixture 已生成到 Packages/MTPCore/Tests/MTPCoreTests/Fixtures/")
}
