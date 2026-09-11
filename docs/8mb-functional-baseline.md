# AudioWRT 8 MB Functional Baseline

The TP-Link TL-WDR4300 v1 is the reference low-end target for AudioWRT. The purpose of the baseline is not to enable every AudioWRT feature on 8 MB flash, but to guarantee a useful network-audio endpoint on constrained hardware.

## Product direction

AudioWRT is primarily a network audio endpoint. Network protocols provide audio to the device and AudioWRT routes it to one of the supported physical outputs.

```text
Network audio receiver
        |
        v
   AudioWRT output
      /      \
Bluetooth    USB Audio
A2DP Source  USB DAC
```

Local USB storage and extroot are not part of the mandatory 8 MB core. They remain useful for larger installations and optional services. A build that wants the guided external-storage stack must request it explicitly with `FEATURES=storage`; the storage CLI, filesystem/USB dependencies and LuCI page are otherwise absent from the baseline.

## Mandatory output baseline

The reference build must attempt to include both:

- Bluetooth A2DP Source output for speakers and headphones.
- USB Audio Class output for USB DACs and sound cards.

Bluetooth is an output capability, not an AudioWRT Extension. The current BlueZ/BlueALSA implementation is intentionally included in the reference build so the firmware-size report exposes its real cost. If it exceeds the image budget, the next optimization target is a reduced BlueZ/BlueALSA build limited to the functionality AudioWRT uses.

## Network input baseline

The first network input target is a lightweight audio-only DLNA/UPnP MediaRenderer. This enables Home Assistant / Music Assistant and other UPnP controllers to send audio to AudioWRT without requiring Spotify Connect, local storage or a full media framework on the router.

AirPlay is the next receiver candidate after the DLNA baseline is measured. Spotify Connect remains optional because its runtime/package footprint is substantially larger on constrained devices.

## Provisioning rules

Provisioning must work on both single-radio and multi-radio devices and must never depend on concurrent AP+STA support on one PHY.

- If the target STA radio differs from the setup AP radio, keep the setup AP while connecting.
- If the target STA uses the setup radio and another radio exists, move the setup AP to the alternate radio first.
- If only one radio exists, stop the setup AP, switch to STA, and restore the setup AP after timeout if association/DHCP fails.
- Selecting an SSID does not pin a BSSID by default, allowing normal roaming on the selected radio.
- Selecting a specific access point explicitly stores its BSSID.

The provisioning wizard and the normal Wi-Fi Client UI must expose the same user model: grouped SSIDs, available bands, channel/signal information, access-point count, and an expandable BSSID list.

## Extension semantics

Extensions are optional audio services, not hardware outputs. The UI must report package state from configured APK repositories:

- `installed`: package is installed.
- `installable`: package is available from a configured repository.
- `unavailable`: package is neither installed nor currently available.

The UI must not display an Install action for unavailable packages.

## Reference acceptance path

The final 8 MB functional milestone is:

```text
fresh flash
  -> provision Wi-Fi/Ethernet
  -> network controller discovers AudioWRT
  -> controller starts playback
  -> AudioWRT routes audio to Bluetooth A2DP Source
  -> optionally switch to a USB Audio Class DAC
```

The current PR establishes the provisioning/output/extension model and deliberately measures the existing Bluetooth stack in the reference build. The DLNA renderer and Bluetooth stack minimization should be implemented and measured as focused follow-up changes so their firmware-size deltas remain attributable.
