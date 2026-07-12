import Testing
@testable import Unison

struct DDCMessageTests {
    // Set volume (VCP 0x62) to 12. Frame per DDC/CI:
    // [0x84, 0x03, 0x62, 0x00, 0x0C, checksum]
    // checksum = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x62 ^ 0x00 ^ 0x0C
    @Test func setVCPFraming() {
        let msg = DDCMessage.setVCP(0x62, 12)
        let cksum: UInt8 = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x62 ^ 0x00 ^ 0x0C
        #expect(msg == [0x84, 0x03, 0x62, 0x00, 0x0C, cksum])
    }

    // Get request for brightness (0x10): [0x82, 0x01, 0x10, checksum]
    @Test func getVCPFraming() {
        let msg = DDCMessage.getVCP(0x10)
        let cksum: UInt8 = 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10
        #expect(msg == [0x82, 0x01, 0x10, cksum])
    }

    // A valid get reply for code 0x10, max 100, current 87.
    @Test func parseValidReply() {
        let bytes: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 100, 0x00, 87, 0x00]
        let r = DDCMessage.parseGetReply(0x10, bytes)
        #expect(r?.current == 87)
        #expect(r?.max == 100)
    }

    // Wrong VCP code in reply -> nil (garbage read).
    @Test func parseWrongCode() {
        let bytes: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 100, 0x00, 87, 0x00]
        #expect(DDCMessage.parseGetReply(0x10, bytes) == nil)
    }
}
