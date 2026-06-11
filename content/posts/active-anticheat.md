+++
title = 'Reverse Engineering the Anticheat on a Private MMO Server'
date = 2026-06-11T10:24:39+01:00
draft = false
+++

I play on a private Aion server. For those unfamiliar, Aion is an MMO from 2009 that NCSoft has largely abandoned in the West, but a community of private servers keeps it alive. The server I play on uses a third-party anticheat called [Active Anticheat](https://active-ac.com), a commercial product sold to private server operators by a developer in Warsaw.

I got curious about what it actually does to my machine. A few evenings with Wireshark, Procmon, Ghidra, and pefile later, here's what I found.

## Starting from almost nothing

My starting point was watching Task Manager while the game launched. A service called PRProt appeared briefly, then disappeared. A kernel driver landed in a temp folder and was gone after reboot. A DLL got injected into the game process. That was enough to go on.

The first useful thing was just running `strings` on the binaries. Most of the AC components are protected with [Themida Code Virtualization](https://www.oreans.com/themida.php), the kernel driver's primary code section is 10.1 MB with entropy 7.62, completely opaque to static analysis. But import tables survive Themida. From those alone you can see what kernel APIs the driver registers: process creation callbacks, thread creation callbacks, image load callbacks, registry monitoring, physical memory access, and `KeBugCheckEx`. Standard kernel anticheat territory, but it tells you what the driver is capable of even when you can't read a single line of its logic.

One string caught my attention: a reference to `iqvw64e.sys`, the [Intel Network Adapter Diagnostic Driver](https://www.loldrivers.io/drivers/1d2cdef1-de44-4849-80e5-e2fa288df681/), a known vulnerable signed driver that's been abused in [BYOVD attacks](https://attack.mitre.org/techniques/T1068/) to kill anticheat and EDR processes from kernel level. The reference is likely a defensive check, detecting whether someone has loaded it, but its presence indicates the AC is aware of this attack vector.

The injected DLL (`clmods64.dll`) is also Themida-packed. I spent time on it statically and got nowhere useful. Dynamically it's more interesting, it connects to the kernel driver via a named event (`AAErrorPortEvent`) and the game process verifies its integrity after injection before proceeding. What it actually does inside the game process remains opaque; it's the black box at the center of the whole system.

## The injection chain

The DLL doesn't inject itself. The sequence is:

1. `ActiveLauncher.exe` writes `clmods64.dll`, the service binary, and the kernel driver to `%LOCALAPPDATA%\Temp\ActiveAnticheat\[serverid]\`
2. The kernel driver is registered as a service and started via `services.exe`, then immediately marked for deletion, it exists in the service registry only long enough to load
3. The game binary (`aion.bin`) sideloads `version.dll` from its own directory, more on this below
4. `version.dll` launches `ij64.exe`, a small injector that uses `CreateRemoteThread` → `LoadLibrary` to load `clmods64.dll` into the game process

The temp folder where all this happens is writable by the current user without elevation. `aaerrport.exe` (the AC service, running as SYSTEM) searches its own directory for DLLs before falling back to System32, specifically `Wtsapi32.dll` and `SspiCli.dll`. A user-level process could drop a malicious DLL there in the window between when `ActiveLauncher.exe` creates the folder and when the service starts. Since the service runs as SYSTEM, the planted DLL would execute at SYSTEM privilege. The fix is straightforward: restrict the temp folder to admin-write-only since `ActiveLauncher.exe` itself runs elevated.

## Network traffic

Capturing traffic while the game launched was more productive than static analysis. Three connections stood out: port 11000 to the AC server, port 2106 for game login, and the game world on a separate host.

Port 11000 is the interesting one. The handshake is RSA-1024 challenge-response, below current recommended minimums but functional. After authentication, the server pushes a blob down to the client that I initially couldn't identify. I could see file path strings in it: localization XMLs, pak files, game binaries. It took a while to realize what I was looking at: a file integrity manifest. The server is telling the client which files to check and what their expected MD5 hashes are.

I confirmed this by finding the same data cached locally in the registry under a key called `fastcheck`, 17KB of binary data. The format is simple: 4-byte entry count, then repeated [1-byte path length + ASCII path + 16-byte MD5]. Parsing it gave me 331 files. The server controls the list entirely; the client has no say.

Parsing the manifest surfaced some oddities. Three files are expected to be zero bytes. All seven language `ui_game_override.xml` files share the same hash, identical files across language folders. The 32-bit and 64-bit `dbghelp.dll` share a hash, meaning a 32-bit binary was deployed to the 64-bit folder. And `bin32\iovation.bin` is in there, [iovation](https://www.iovation.com/) is a commercial device fingerprinting service, not NCSoft code, whose presence and data collection scope isn't disclosed to players.

## The credential problem

While analyzing the launch sequence I noticed the launcher spawning `ActiveLauncher.exe` with credentials as plaintext command-line arguments, visible to any process monitor on the system. The stored credentials in the registry are RC4-encrypted with a hardcoded key, a short repeating pattern recoverable in minutes with a hex editor.

The fix is simpler than expected. The launcher doesn't check for a parent process. Running `ActiveLauncher.exe` directly without credential arguments works fine, and the game prompts for a password on its own login screen. Credentials never touch the command line or the registry. Deleting the registry key afterward leaves nothing stored.

## The kernel driver's device

Running [Sysinternals accesschk](https://learn.microsoft.com/en-us/sysinternals/downloads/accesschk) on `active64.sys`'s device object revealed an Everyone entry with full access in the security descriptor:

```
D:P(A;;GA;;;SY)(A;;GRGWGX;;;BA)(A;;GA;;;WD)
```

Any unprivileged process on the machine can open a handle to the kernel driver and send it IOCTLs directly. What commands it accepts is unknown, the code is Themida-encrypted, but the exposure is unconditional. Major commercial anticheats restrict their devices to SYSTEM and Administrators. This is hardcoded in protected code behind a Microsoft-signed binary, so it's not fixable from the outside.

A practical note: `active64.sys` keeps running after you close the game. `sc stop PRProt && sc stop AAErrorPort` stops both components. The driver is already marked for deletion on reboot, but stopping it immediately after gaming reduces the window during which a kernel driver with system-wide monitoring and a world-accessible device is running on your machine for no reason.

## What the anticheat doesn't prevent

I was curious whether the AC would block memory editors. It doesn't strip `PROCESS_VM_WRITE` from handles opened to the game process, something EAC, BattlEye, and Vanguard all do via [`ObRegisterCallbacks`](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/nf-wdm-obregistercallbacks), which lets them deny memory write access even to admin processes.

To test this I looked at [ShugoConsole](https://github.com/MrBulldops/ShugoConsole), a popular Aion settings editor that uses `WriteProcessMemory` to modify game values. It works fine with the AC running. The AC's approach is detect-and-ban rather than prevent, if your tool isn't in the signature list, the writes go through.

This led me to check the detection signatures. The driver's string table (readable before Themida initializes) contains `ShugoConsoleWidget`, the window class it passes to `FindWindow` to detect ShugoConsole. ShugoConsole 1.1.3+ is a Qt5 application. Qt5 registers windows as `Qt5QWindowToolSaveBits`, not the object class name. `FindWindow('ShugoConsoleWidget', $null)` returns 0 with ShugoConsole running. I tested it. No detection. The signature has been dead against any modern build.

## The game binary

Worth a quick note since it confused me initially: `aion.bin` is not some exotic format despite the extension. It's a standard PE32+ executable, signed by NCsoft Corp in 2015. It's 0.6 MB on disk but carries a custom packed section that expands to roughly 1.5 GB at runtime, the standard PE sections have zero raw size and are allocated entirely in memory by the unpacker.

The `version.dll` sideload that the private server uses to hook the game isn't the operator's innovation. NCSoft shipped the binary with an explicit import of `VERSION.dll`. Windows searches the application directory before System32, so any DLL placed there loads automatically. The private server drops their proxy there to redirect network connections. They inherited this attack surface from NCSoft and can't change it without rebuilding a client they don't have source for.

## What remains unknown

The Themida-protected components are genuinely opaque. The kernel driver monitors processes, threads, image loads, and registry operations. It checks BCD flags at boot through the kernel BCD API (not visible in Procmon, the 5,900 BCD events I captured were all Windows WMI). The injected DLL communicates with the driver and runs inside the game process. What specific detections fire, what data goes to the server, what triggers a ban, this would require devirtualizing Themida, which is a different project.

The driver certificate expires July 14, 2026. That's probably the more pressing operational concern for the server operator than anything here.
