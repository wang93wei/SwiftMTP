# MTPCore

MTP/PTP 协议纯逻辑层(Swift)。不依赖 app/USB/libusb,可独立 `swift test`。

## 黄金契约(Golden Contract)

`Tests/MTPCoreTests/Fixtures/*.json` 由 Go `Native/encoding_golden_test.go` 的
`TestGenerateFixtures` 生成(用 `mtp.Encode` 编码已知结构体 = 真理源)。
Go `TestGoldenDecode` 与 Swift `EncodingGoldenTests` 都读同一 JSON 做 decode 断言,
两端互为交叉验证,任一端实现回归都会被立即捕获。

当前 fixture:

| Fixture | 结构体 | 覆盖点 |
|---|---|---|
| `objectinfo_simple.json` | `ObjectInfo` | 基础字段 + 空时间(zero time → nil) |
| `objectinfo_cjk.json` | `ObjectInfo` | CJK 文件名 + ModificationDate |
| `storageinfo_simple.json` | `StorageInfo` | 容量 + VolumeLabel |
| `uint32array_simple.json` | `Uint32Array` | u32 长度前缀数组 |
| `deviceinfo_simple.json` | `DeviceInfo` | 多字符串 + 数组字段 |

**改 fixture 流程**:

1. 改 Go `Native/encoding_golden_test.go` 中 `TestGenerateFixtures` 的输入 struct;
2. `cd Native && go test -run TestGenerateFixtures` 重新生成 JSON;
3. `git add` 提交更新后的 `Fixtures/*.json`;
4. 两端 decode 自动验证对齐(Swift `swift test` + Go `go test`)。

> 一致性校验见 `Scripts/check_encoding_fixtures.sh`(Task 12),CI 中可防止 fixture 漂移。

## 线序依据(Wire Order)

所有结构体字段顺序严格对应 Go
`Native/vendor/github.com/ganeshrvel/go-mtpfs/mtp/types.go`,
小端字节序对应 `encoding.go` `byteOrder = binary.LittleEndian`。
Swift 侧由每个结构体的 `init(from:)` 显式逐字段读取(替代 Go 的 reflect-based Decode),
线序在一处维护、一处正确。

- **整数**:小端(`MTPReader.readU8/16/32/64`)
- **MTP 字符串**:UCS-2,1 字节 sz(codepoint 数,含尾零)→ sz 个小端 uint16 → 去尾零(`encoding.go` `decodeStr` / `readMTPString`)
- **MTP 时间**:三变体兼容(`encoding.go` `decodeTime` / `readMTPTime`)
  - 标准 `"yyyyMMdd'T'HHmmss"`(UTC)
  - 三星尾点(`TrimRight(".")`)
  - Jolla 尾 `Z`(`TrimRight("Z")`)
  - Nokia 数字时区 `"yyyyMMdd'T'HHmmssZZZZZ"`(回退)

## 运行测试

```bash
cd Packages/MTPCore && swift test   # Swift 侧,21 tests
cd Native && go test ./...           # Go 侧(含黄金契约 generate + decode)
```
