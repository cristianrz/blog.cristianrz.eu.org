+++
title = 'The Reboot Problem: Why Most Operating Systems Can\'t Defend Against a Compromised Root'
date = 2026-05-22T11:36:38+01:00
draft = false
+++

Assume malware has run on your machine and obtained root. After a reboot, is it still there? For most operating systems the answer is yes. The OS itself offers no structural resistance once root is obtained — it can write to system directories, replace binaries, install kernel modules, modify boot configuration. None of this requires exploiting a vulnerability. It's just what root can do by design.

The threat we're reasoning about throughout is specifically this: malware that has obtained root and wants to survive a reboot at the OS level. Not keyloggers in `~/.bashrc` — those are a different layer. Can the base OS be modified without detection, and will those modifications persist?

## The Boot Chain and Where It Breaks

When a machine starts, execution flows through: firmware → bootloader → kernel → userspace. Each link is supposed to verify the next.

[UEFI Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot) checks that the bootloader is signed by a trusted key — on most PCs, Microsoft's. The bootloader verifies the kernel. Then the kernel boots, mounts the root filesystem, and executes whatever is there. Unverified. Any root process can plant something in `/usr` or install a kernel module, and it will survive the next reboot unchallenged.

There's a subtler gap too: the initramfs. This small in-memory filesystem runs between the bootloader and the real root — it handles LUKS decryption and driver loading. Most distros sign the kernel but ship the initramfs as a separate unsigned file. A tampered initramfs can intercept your disk encryption passphrase before the kernel even sees it, and Secure Boot will never notice because it only verified the kernel binary. The fix is the [Unified Kernel Image (UKI)](https://uapi-group.org/specifications/specs/unified_kernel_image/) — a single signed EFI binary containing the kernel, initramfs, and command line together. If any component is modified, the signature breaks. Fedora 40 added support for this; Silverblue cannot use UKIs due to its hard dependency on GRUB.

Secure Boot also has a more fundamental problem. It checks that the bootloader is signed, not that it's safe. The [BlackLotus bootkit](https://www.welivesecurity.com/2023/03/01/blacklotus-uefi-bootkit-myth-confirmed/) demonstrated this in 2023: replace the modern bootloader with an older, legitimately signed Microsoft bootloader that had a known vulnerability. Secure Boot accepts it — the signature is valid. This is badness enumeration: maintain a blocklist of known-bad binaries, reject those. It fails the same way antivirus fails. Microsoft maintains a revocation database (DBX) for this, but distributing those updates consistently across millions of heterogeneous machines is an unsolved operational problem. The attack surface is every binary ever signed in the Microsoft chain.

The correct model is goodness enumeration: only run binaries you've explicitly signed, reject everything else. Custom Secure Boot keys do this — you replace Microsoft's keys with your own, sign only your own binaries, and the pool of trusted code becomes narrow and controlled. ChromeOS and GrapheneOS do this with hardware-burned keys that cannot be replaced by any software running on the machine.

## dm-verity, Lockdown, and Anchoring Trust in Hardware

[dm-verity](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/verity.html) is what actually protects the root filesystem. It precomputes a Merkle tree of hashes over every block of a filesystem image. The root hash is stored somewhere the attacker cannot modify. When the kernel reads any block, it verifies it against the hash tree in real time — a modified block causes a mismatch and the kernel refuses to use it. This is not a filesystem permission. Root cannot override it with `sudo`. It operates at the kernel's block layer. ChromeOS has used it on its root partition since launch; Android since version 4.4.

dm-verity is only as strong as where the root hash lives. If an attacker can swap the hash to match a tampered filesystem, the verification is worthless. On ChromeOS the root hash is anchored to a [Google Security Chip](https://security.googleblog.com/2019/10/titan-m-makes-pixel-4-our-most-secure.html) burned into hardware at manufacture. On Pixel phones it's a [Titan chip](https://security.googleblog.com/2021/10/pixel-6-setting-new-standard-for-mobile.html). On Apple Silicon it's the Secure Enclave. These hardware roots of trust are what separate the top-tier systems from everything else — software can be replaced, silicon burned at the factory cannot. General-purpose PCs have no equivalent. The firmware is from the motherboard manufacturer, the OS from a separate vendor, and the signing chain has too many owners to be airtight.

Even with dm-verity protecting the filesystem, root can still interact with the running kernel directly — loading unsigned kernel modules, writing to kernel memory. [Kernel lockdown mode](https://www.kernel.org/doc/html/latest/security/lockdown-lsm.html) (`lockdown=integrity`) closes these paths: root cannot load unsigned modules, write to kernel memory, or replace the running kernel via kexec. Without it, malware could patch the running kernel in memory even if it can't touch the filesystem. Ubuntu has enabled lockdown by default when Secure Boot is active since 20.04; Fedora hasn't made the same call, largely because it breaks DKMS-based drivers like Nvidia's proprietary module.

## Physical Attacks, FDE, and the Two-Boot Setup

Full disk encryption is commonly treated as covering physical attack scenarios. It covers one: someone who steals the drive and tries to read it cold, without ever booting into your OS. It doesn't cover an attacker who has brief physical access while you're away — they replace your bootloader with a malicious copy, wait for you to boot and type your passphrase, and capture it. Your encrypted disk is now open to them.

The fix is TPM-sealed key storage. The LUKS key is sealed to TPM measurements that capture the exact state of the boot chain. If the bootloader is replaced, measurements change, the TPM refuses to unseal the key, and you're warned before typing anything. This is what [Heads](https://osresearch.net/) firmware implements, combined with a USB security key that gives a visual confirmation — green LED means the boot chain matches what it was last time you verified it, red means something changed.

A different approach to physical and escalation threats is a two-boot setup — no special hardware required. Configure two separate boot entries: a daily-use entry that boots into an unprivileged user account with no `sudo` access, and an admin entry with sudo but no internet connection. Malware running in the daily-use session has no path to root and therefore can't write to system directories or install persistent services outside the user's home. Updates are applied by rebooting into admin mode, running them, then rebooting back. It's architecturally similar to how ChromeOS works: not "root is protected by good defaults" but "the path to root doesn't exist in normal operation." The limitation is that userspace persistence — dotfiles, user-level systemd services — is still possible, but OS-level persistence is blocked.

## Where Each OS Stands

Each OS below is assessed against 7 criteria: whether it structurally prevents privilege escalation to root; and whether root can modify the kernel, OS files, or bootloader in a live session and via physical access. The criterion is binary — does the protection hold without relying on bugs not existing?

**ChromeOS / GrapheneOS — 7/7**

The reference implementations. Hardware-anchored trust from silicon to filesystem, dm-verity on root, no root access path in normal operation, atomic signed image updates applied to an inactive partition and swapped on next boot. Physical attacks are cryptographically prevented. [ChromeOS's update model](https://www.chromium.org/chromium-os/chromiumos-design-docs/filesystem-autoupdate/) — full signed images, automatic rollback on failure — is what dm-verity requires and what general-purpose Linux is only now building toward with [bootc](https://containers.github.io/bootc/).

**macOS on Apple Silicon — 6/7**

The [Signed System Volume](https://support.apple.com/guide/security/signed-system-volume-security-secd698747c9/web) seals every OS file in a Merkle tree verified at runtime. System Integrity Protection prevents root from modifying system files in a live session. The chain terminates at the Secure Enclave. The one gap versus ChromeOS: admin users have `sudo` by design. On a Chromebook there is no path to root in normal operation; on a Mac there is.

**NitroPad + Ubuntu (two-boot + lockdown) — 5/7**

[The NitroPad](https://www.nitrokey.com/products/nitropads) uses [Coreboot](https://www.coreboot.org/) and [Heads](https://osresearch.net/), replacing proprietary UEFI entirely. The bootloader lives in firmware, not on the EFI partition where root could overwrite it. Intel ME is disabled. A [Nitrokey](https://www.nitrokey.com/) USB key holds TPM-sealed boot measurements — tamper with the firmware or bootloader and the disk won't auto-decrypt. Add a two-boot setup and `lockdown=integrity` and you cover escalation prevention, kernel protection, and bootloader integrity. The remaining gap is dm-verity on OS files.

The same 5/7 is achievable on regular hardware: Fedora Workstation with UKI, custom Secure Boot keys with the signing key stored in the TPM (so root cannot extract and sign a malicious UKI), lockdown, and a two-boot setup. This is a weekend's work using [sbctl](https://github.com/Foxboron/sbctl) and systemd's UKI tooling — [well documented](https://www.zhookchristopher.com/full-uefi-secure-boot-on-fedora-using-signed-initrd-and-systemd-boot/).

**ChromeOS Flex — 3/7**

ChromeOS without the Google Security Chip. dm-verity still runs and is enforced — root genuinely cannot modify OS files — and there's no root path in normal operation. What's lost is the hardware anchor, so physical attack vectors open up. For a threat model that doesn't include physical access, [ChromeOS Flex](https://chromeos.google/products/chromeos-flex/) on old x86 hardware is an unusually strong choice with zero configuration.

**Qubes OS — 3/7**

[Qubes](https://www.qubes-os.org/) isolates everything in VMs and accepts that any given VM may be compromised. AppVMs boot from read-only snapshots of template VMs — OS-level changes don't survive a reboot. Root in an AppVM cannot reach dom0, which controls the bootloader, hypervisor, and all other VMs, without a Xen hypervisor escape. The weakness is physical access: without Heads there's no verified boot chain. Qubes on a NitroPad with Heads is the strongest general-purpose configuration available today.

**Fedora Workstation / Arch (two-boot + lockdown, no custom keys) — 2/7**

With two-boot and lockdown, escalation and kernel modification are covered. With UKI on Fedora, the initramfs gap is closed. Without custom keys the Secure Boot chain remains badness enumeration, and physical access is not well defended. A practical daily driver with real improvements that stop short of the full picture.

**[Secureblue](https://secureblue.dev/) — 1/7**

Ships `lockdown=confidentiality` by default, plus [hardened malloc](https://github.com/GrapheneOS/hardened_malloc) system-wide, restricted user namespaces, and ptrace restrictions. These meaningfully raise the bar for exploitation — reaching root is harder. But once root is obtained the OS is structurally unprotected: no dm-verity, no sealed images. Silverblue's immutability is policy-based and bypassed trivially with root access. [composefs](https://github.com/containers/composefs) in Fedora 42 moves toward file-level verification, but without the root hash anchored in a signed UKI, root can still update the hash store to match tampered files.

**Windows — 0/7**

No structural answer to OS file modification by root. System files are fully writable by admin processes. Secure Boot uses the Microsoft chain with all its badness-enumeration problems. Windows S Mode is architecturally interesting in one specific way — the AppContainer prevents Store apps from triggering UAC, blocking escalation without relying on bugs — but once root is obtained the underlying OS is as exposed as regular Windows.

## Where Linux Is Heading

The pieces are converging. composefs + fs-verity provides per-file cryptographic verification. [Sealed images](https://fedoraproject.org/wiki/Changes/Unified_Kernel_Support_Phase_2) — composefs with fs-verity, root hash in a signed UKI — are in experimental testing as of mid-2025, no bare-metal ISO yet. bootc replaces ostree's file-by-file updates with whole-image updates that are naturally compatible with dm-verity. When sealed images ship as a Fedora default with official signing keys, Silverblue moves from its current position to something close to ChromeOS Flex using the existing distro signing chain — no custom hardware required.

The gap that configuration cannot close is the hardware trust anchor. Fedora can have dm-verity and signed images. It cannot have a hardware-burned key that makes the chain physically tamper-proof without controlling the hardware. That's the irreducible advantage of ChromeOS and GrapheneOS — and for remote-only threat models, sealed images will close the practical gap.

Stock Silverblue, standard Ubuntu, Windows — they're relying on attackers not bothering to exploit gaps that demonstrably exist. The better-configured options described here are achievable today, mostly with software and a few hours.
