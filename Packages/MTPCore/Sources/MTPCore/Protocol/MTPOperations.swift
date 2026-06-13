import Foundation

// MARK: - Operations 只读层
// 对照 Go ops.go,本文件实现 spike 只读闭环所需的 6 个读操作。
// getData<T> 泛型模板(runTransaction + MemoryDataSink + decode)包装 5 个结构体读操作;
// getObject 流式写 sink(不 decode,大文件传 FileHandle 写盘)。

extension MTPDevice {
    /// 只读操作通用模板。对照 Go ops.go:52 GetData。
    /// runTransaction(dest: MemoryDataSink) 收 DATA → decode 成 T。
    /// 注:USB 成功但 decode 失败会 throw MTPDecodeError(调用方需区分)。
    private func getData<T: MTPDecodable>(
        code: OperationCode,
        params: [UInt32] = [],
        as type: T.Type = T.self
    ) throws -> T {
        var req = MTPRequest(code: code, params: params)
        let sink = MemoryDataSink()
        _ = try runTransaction(request: &req, dest: sink)
        return try decode(Data(sink.data), as: type)
    }

    /// OC=0x1001。对照 Go ops.go:65。
    /// ⚠️ 可 OpenSession 前调(P4 兜底用:GetDeviceInfo 无需 session)。
    func getDeviceInfo() throws -> DeviceInfo {
        try getData(code: .getDeviceInfo, as: DeviceInfo.self)
    }

    /// OC=0x1004。对照 Go ops.go:71。须 OpenSession 后。
    func getStorageIDs() throws -> [UInt32] {
        try getData(code: .getStorageIDs, as: Uint32Array.self).values
    }

    /// OC=0x1005。对照 Go ops.go:145。须 OpenSession 后。
    func getStorageInfo(storageID: UInt32) throws -> StorageInfo {
        try getData(code: .getStorageInfo, params: [storageID], as: StorageInfo.self)
    }

    /// OC=0x1007。对照 Go ops.go:152。3 参,通配值见 MTPConstants。须 OpenSession 后。
    func getObjectHandles(storageID: UInt32, formatCode: UInt32, parent: UInt32) throws -> [UInt32] {
        try getData(code: .getObjectHandles, params: [storageID, formatCode, parent],
                    as: Uint32Array.self).values
    }

    /// OC=0x1008。对照 Go ops.go:159。须 OpenSession 后。
    func getObjectInfo(handle: UInt32) throws -> ObjectInfo {
        try getData(code: .getObjectInfo, params: [handle], as: ObjectInfo.self)
    }

    /// OC=0x1009。对照 Go ops.go:207。流式收文件字节进 sink(不 decode)。
    /// ⚠️ 大文件必须传 FileHandle 写盘(MemoryDataSink 全量进内存,仅测试/小对象用)。
    func getObject(handle: UInt32, to sink: MTPDataSink,
                   progress: @escaping (Int64) -> Bool = { _ in true }) throws {
        var req = MTPRequest(code: .getObject, params: [handle])
        _ = try runTransaction(request: &req, dest: sink, progress: progress)
    }
}
