import Carbon.HIToolbox

/// Global Option+Space through Carbon's RegisterEventHotKey. It consumes the keystroke,
/// so the front app never receives the space, and it needs no Input Monitoring permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    fileprivate let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue().onTrigger()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey),
            EventHotKeyID(signature: OSType(0x4C57_4658), id: 1),
            GetApplicationEventTarget(), 0, &ref)
    }
}
