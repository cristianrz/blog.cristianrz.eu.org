---
title: "An Analysis of GrapheneOS's Server Infrastructure"
date: 2026-05-31
---

I was poking around the [GrapheneOS infrastructure repo](https://github.com/GrapheneOS/infrastructure) last week, just curious how they build things. First thing I noticed: every single server runs Arch Linux. DNS nodes, mail servers, the lot. You can verify it directly — every package list includes `pacman-contrib` and `pacutils`, which are Arch-specific and don't exist on any other distro. The [`deploy-initial-vps` script](https://github.com/GrapheneOS/infrastructure/blob/main/deploy-initial-vps) checks for the Arch ISO before doing anything else: `ssh $remote '[[ $(grep IMAGE_ID /etc/os-release) = "IMAGE_ID=archlinux" ]]'`. Arch on a server is unusual. I kept reading.

Arch is rolling-release — updates arrive continuously rather than in tested batches. To be fair, they do pin the LTS kernel on every machine, which is the slower-moving stable kernel. But the rest of the userspace rolls forward with no immutability and no verified boot. That's the opposite of how they approach the phone OS.

The DNS nodes compound this. A DNS server has one job. GrapheneOS's [DNS node package list](https://github.com/GrapheneOS/infrastructure/tree/main/packages) has 42 entries — Neovim, Fish shell, htop, mtr, nmap, strace, iperf, the full package manager. The phone OS strips everything unnecessary to reduce attack surface. The servers install the full toolkit everywhere because it's convenient. Those are contradictory positions.

The containers aren't really containers either. The DNS secondary nodes and mail server run inside what are described as isolated environments, but they're bootstrapped with `pacstrap` — the same tool used to install Arch from scratch onto bare metal. Complete Arch install inside, package manager included. The [hosts that run containers](https://github.com/GrapheneOS/infrastructure/blob/main/hosts.sh) have `arch-install-scripts` installed, and nowhere else does. The only difference from a standalone server is no kernel and no bootloader. That's not what most people mean by container isolation.

Then I found this in [`etc/unbound/unbound.conf`](https://github.com/GrapheneOS/infrastructure/blob/main/etc/unbound/unbound.conf):

```
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 1.0.0.1@853#cloudflare-dns.com
```

GrapheneOS runs [over 40 DNS servers across 16 locations](https://grapheneos.org/articles/grapheneos-servers) with anycast routing and custom geographic load balancing. The implicit reason for building that is independence — no third party seeing your query patterns or manipulating responses. Then every one of those servers forwards its own DNS queries to Cloudflare. Cloudflare sees what domains every GrapheneOS server looks up, when, and how often. There's no explanation for this anywhere in their public documentation.

The jurisdiction situation is similarly awkward. GrapheneOS [left OVH late last year](https://www.datacenterdynamics.com/en/news/grapheneos-migrates-workloads-off-of-ovh-cites-issues-with-frances-digital-privacy-policy/) citing France's support for Chat Control — proposed EU legislation requiring scanning of private messages. The framing was principled: France isn't safe for a privacy project. The forum, Matrix server, Mastodon instance, and attestation service [moved to netcup servers in Manassas, Virginia](https://grapheneos.org/articles/grapheneos-servers). Netcup is a German company, but these are US machines. US jurisdiction means National Security Letters — which can demand data and forbid disclosure — FISA courts, and a surveillance apparatus that's by most measures more expansive than what they objected to in France. Maybe it was a pragmatic necessity of moving quickly. But it wasn't mentioned in the announcement.

On governance: GrapheneOS was founded by Daniel Micay (`thestinger`). In 2026, after a period of public conflict — including [accusing Louis Rossmann of being "complicit in attempted murder"](https://privatephoneshop.com/why-we-no-longer-sell-phones-with-grapheneos/) for leaving a YouTube comment — he announced he was stepping down as lead developer and Foundation director. [Canadian federal corporate records still listed him as a director as of late 2025](https://factually.co/fact-checks/technology/who-runs-grapheneos-after-daniel-micay-14e426), two and a half years later. The [FUNDING.yml](https://github.com/GrapheneOS/infrastructure/blob/main/.github/FUNDING.yml) lists his personal GitHub account as the sole funding recipient. His dotfiles are throughout the server configs — his Neovim theme, shell preferences, keybindings. The production mail server has `mutt` and `s-nail` installed. You install those when you personally read mail directly on the server.

[GrapheneOS reports around 400,000 active users](https://en.wikipedia.org/wiki/GrapheneOS). One person's personal setup serves all of them.

When Micay stepped down he said signing infrastructure would be ["replicated in multiple locations and verified against each other"](https://lemmy.ca/post/568614). The update signing keys live on air-gapped machines — good practice — but controlled by the same person whose dotfiles are on the servers, whose GitHub is the funding recipient, who is still listed as a director. There's no public evidence the replication happened. The repo still looks like one person's deployment scripts.

The OS itself is fine regardless of all this — verified boot means existing installations can't be silently compromised even if every server were taken over. But shipping new security patches depends on infrastructure and keys that appear to live with one person. If Micay walked away, got hit by a bus, or got served an NSL, the community infrastructure has no visible succession plan.

I still use GrapheneOS. [Cellebrite lists it as one of the few Android devices it can't extract data from](https://discuss.techlore.tech/t/claims-made-by-forensics-companies-their-capabilities-and-how-grapheneos-fares/8653) — that's real. The kernel hardening, the memory allocator, the sandboxing all work. None of what's above changes that.

But there's a sharp gap between how adversarially they think about the phone OS and how they've built everything around it. On the phone: minimal surface, assume everything is hostile, strip everything unnecessary. On the servers: one person's preferred tools, full installs everywhere, Cloudflare forwarding on infrastructure built to avoid Cloudflare. It reads like someone very good at mobile security built the supporting systems himself without applying the same rigour to the scaffolding.
