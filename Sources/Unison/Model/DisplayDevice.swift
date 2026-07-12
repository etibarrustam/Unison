enum BrightnessBackend {
    case builtin
    case ddc(String)   // DDCDisplay.id
}

struct DisplayDevice: Identifiable {
    let id: String
    var name: String
    var backend: BrightnessBackend
    var brightness: Double
}
