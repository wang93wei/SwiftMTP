# External Constraints

Checked on 2026-07-26.

## libusb

- Official project: <https://github.com/libusb/libusb>
- API reference: <https://libusb.sourceforge.io/api-1.0/>
- Current API docs identify libusb 1.0.30 as a C userspace USB library supporting macOS, synchronous/asynchronous I/O, bulk/interrupt transfers, hotplug where available, and thread-safe operation.
- `libusb_claim_interface` is required before endpoint I/O and exposes structured busy/no-device errors:
  <https://libusb.sourceforge.io/api-1.0/group__libusb__dev.html>
- Only asynchronous transfers can be cancelled after submission:
  <https://libusb.sourceforge.io/api-1.0/libusb_io.html>
- Resource release must not race with active operations; transfer buffers are owned by libusb until completion:
  <https://libusb.sourceforge.io/api-1.0/libusb_caveats.html>

libusb supplies USB transport, not MTP/PTP session, transaction, container, storage, object, or transfer semantics.

## Apple Interop

- Apple documents direct user-space USB access through IOKit `IOUSBLib.h`:
  <https://developer.apple.com/documentation/iokit/iousblib_h>
- SwiftPM supports C-family targets and system-library targets:
  <https://developer.apple.com/documentation/PackageDescription/Target>

The repository currently has no libusb headers or module map, so a Swift implementation that keeps libusb needs an explicit C module/binary packaging strategy.

## MTP Files Above 4 GiB

- AOSP documents that ObjectInfo compressed size is an unsigned 32-bit field, while the ObjectSize property can provide the true 64-bit size:
  <https://android.googlesource.com/platform/prebuilts/fullsdk/sources/android-30/+/refs/heads/androidx-wear-wear-input-release/android/mtp/MtpDevice.java>
- AOSP's MTP server treats `0xFFFFFFFF` in SendObjectInfo as “size is at least 0xFFFFFFFF” and may return ObjectTooLarge when the target storage cannot accept it:
  <https://android.googlesource.com/platform/frameworks/av/+/e9154ce/media/mtp/MtpServer.cpp>
- Android also defines vendor partial-object operations with 64-bit offsets, but those operations are outside the current SwiftMTP production capability set:
  <https://android.googlesource.com/platform/frameworks/av/+/master/media/mtp/mtp.h>

The migration therefore applies two exact boundaries:

- ObjectInfo compressed size is exact through `0xFFFFFFFE`; sizes `>= 0xFFFFFFFF` use the sentinel.
- A data-container length includes its 12-byte header, so payloads through `0xFFFFFFF3` can encode `payload + 12`; larger payloads use the sentinel.

Both boundaries receive exact-wire fixtures. Device rejection becomes an explicit unsupported/object-too-large error. For large downloads, Swift queries the ObjectSize property when supported and never silently narrows the size.

## Context7 Result

Context7 was queried for official libusb documentation but returned no authoritative libusb library ID. Official libusb and Apple primary sources were used instead.
