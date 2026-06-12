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

func loadFixture(t *testing.T, name string) fixtureJSON {
	t.Helper()
	path := filepath.Join(fixtureDir(t), name+".json")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	var fx fixtureJSON
	if err := json.Unmarshal(b, &fx); err != nil {
		t.Fatalf("unmarshal fixture %s: %v", name, err)
	}
	return fx
}

// TestGoldenDecode 验证 Go mtp.Decode 对 fixture 解码正确(Go 侧黄金契约成立)。
// Swift 侧将用同一 fixture 对齐(见 MTPCoreTests/EncodingGoldenTests.swift)。
func TestGoldenDecode(t *testing.T) {
	// ObjectInfo simple
	fx := loadFixture(t, "objectinfo_simple")
	raw, err := hex.DecodeString(fx.Hex)
	if err != nil {
		t.Fatalf("hex decode: %v", err)
	}
	var obj mtp.ObjectInfo
	if err := mtp.Decode(bytes.NewReader(raw), &obj); err != nil {
		t.Fatalf("decode ObjectInfo: %v", err)
	}
	var exp struct {
		StorageID      uint32 `json:"storageID"`
		ObjectFormat   uint16 `json:"objectFormat"`
		CompressedSize uint32 `json:"compressedSize"`
		ParentObject   uint32 `json:"parentObject"`
		Filename       string `json:"filename"`
	}
	if err := json.Unmarshal(fx.Expected, &exp); err != nil {
		t.Fatalf("unmarshal expected: %v", err)
	}
	if obj.StorageID != exp.StorageID || obj.Filename != exp.Filename ||
		obj.CompressedSize != exp.CompressedSize || obj.ParentObject != exp.ParentObject ||
		obj.ObjectFormat != exp.ObjectFormat {
		t.Fatalf("ObjectInfo mismatch: got %+v, want %+v", obj, exp)
	}

	// ObjectInfo CJK + 时间
	fx2 := loadFixture(t, "objectinfo_cjk")
	raw2, _ := hex.DecodeString(fx2.Hex)
	var obj2 mtp.ObjectInfo
	if err := mtp.Decode(bytes.NewReader(raw2), &obj2); err != nil {
		t.Fatalf("decode ObjectInfo2: %v", err)
	}
	var exp2 struct {
		Filename         string  `json:"filename"`
		CompressedSize   uint32  `json:"compressedSize"`
		ModificationTime float64 `json:"modificationTime"`
	}
	_ = json.Unmarshal(fx2.Expected, &exp2)
	if obj2.Filename != exp2.Filename {
		t.Fatalf("CJK filename mismatch: got %q, want %q", obj2.Filename, exp2.Filename)
	}
	if obj2.ModificationDate.Unix() != int64(exp2.ModificationTime) {
		t.Fatalf("modtime mismatch: got %v, want %v", obj2.ModificationDate.Unix(), int64(exp2.ModificationTime))
	}

	// StorageInfo
	fx3 := loadFixture(t, "storageinfo_simple")
	raw3, _ := hex.DecodeString(fx3.Hex)
	var st mtp.StorageInfo
	if err := mtp.Decode(bytes.NewReader(raw3), &st); err != nil {
		t.Fatalf("decode StorageInfo: %v", err)
	}
	var exp3 struct {
		MaxCapability    uint64 `json:"maxCapability"`
		FreeSpaceInBytes uint64 `json:"freeSpaceInBytes"`
		VolumeLabel      string `json:"volumeLabel"`
	}
	_ = json.Unmarshal(fx3.Expected, &exp3)
	if st.MaxCapability != exp3.MaxCapability || st.FreeSpaceInBytes != exp3.FreeSpaceInBytes ||
		st.VolumeLabel != exp3.VolumeLabel {
		t.Fatalf("StorageInfo mismatch: got %+v", st)
	}

	// Uint32Array
	fx4 := loadFixture(t, "uint32array_simple")
	raw4, _ := hex.DecodeString(fx4.Hex)
	var arr mtp.Uint32Array
	if err := mtp.Decode(bytes.NewReader(raw4), &arr); err != nil {
		t.Fatalf("decode Uint32Array: %v", err)
	}
	var exp4 struct {
		Values []uint32 `json:"values"`
	}
	_ = json.Unmarshal(fx4.Expected, &exp4)
	if len(arr.Values) != len(exp4.Values) {
		t.Fatalf("Uint32Array len mismatch: got %d, want %d", len(arr.Values), len(exp4.Values))
	}

	// DeviceInfo
	fx5 := loadFixture(t, "deviceinfo_simple")
	raw5, _ := hex.DecodeString(fx5.Hex)
	var di mtp.DeviceInfo
	if err := mtp.Decode(bytes.NewReader(raw5), &di); err != nil {
		t.Fatalf("decode DeviceInfo: %v", err)
	}
	var exp5 struct {
		Manufacturer string `json:"manufacturer"`
		Model        string `json:"model"`
	}
	_ = json.Unmarshal(fx5.Expected, &exp5)
	if di.Manufacturer != exp5.Manufacturer || di.Model != exp5.Model {
		t.Fatalf("DeviceInfo mismatch: got %s/%s", di.Manufacturer, di.Model)
	}
}
