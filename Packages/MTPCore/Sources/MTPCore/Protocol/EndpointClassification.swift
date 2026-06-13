import Foundation

/// 端点分类结果。nil 表示该类端点未找到。
public struct EndpointClassification: Equatable {
    public let sendEP: UInt8?   // OUT + BULK
    public let fetchEP: UInt8?  // IN + BULK
    public let eventEP: UInt8?  // IN + INTERRUPT
}

/// 按 MTP 拓扑分派端点(对应 Go select.go:27-35)。
/// 给一组 EndpointSnapshot,按方向(address&0x80)+ 传输类型(attributes&0x03)分派。
/// 后出现的同类端点覆盖前者(对齐 Go switch 顺序赋值)。
public func classifyEndpoints(_ eps: [EndpointSnapshot]) -> EndpointClassification {
    var send: UInt8? = nil
    var fetch: UInt8? = nil
    var event: UInt8? = nil
    for ep in eps {
        let isBulk = ep.transferType == 0x02
        let isIntr = ep.transferType == 0x03
        if !ep.isIn && isBulk { send = ep.address }
        else if ep.isIn && isBulk { fetch = ep.address }
        else if ep.isIn && isIntr { event = ep.address }
    }
    return EndpointClassification(sendEP: send, fetchEP: fetch, eventEP: event)
}

/// 候选成立判定:恰好 3 端点 + 三类齐全(对应 Go select.go:23,37)。
public func isMTPCandidate(_ eps: [EndpointSnapshot]) -> Bool {
    guard eps.count == 3 else { return false }
    let c = classifyEndpoints(eps)
    return c.sendEP != nil && c.fetchEP != nil && c.eventEP != nil
}
