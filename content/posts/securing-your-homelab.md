---
title: "Securing Your Homelab: Navigating the Complexities of Remote Access and Trust"
date: 2023-03-13
---

Trying to set up my homelab and have it be reachable from the internet I had serious problems getting to where I wanted to be, although I never expected it was going to be that difficult.

Being very pro-privacy pro-security my goals where:

- Access my services from anywhere, including my phone
- Create trust between server and client that doesn't involve 3rd parties, ideally trust on first use. Assume all middle-men are compromised.
- Have end to end encrypted connections.
- Clients can only talk to services once I know they are clients who I trust.
- Have a usable latency/bandwidth.
- Setup once/work forever. The kind of thing I would install on my mom's devices so she can use my Nextcloud instance forever.
- Assume services security is flawed and they need a gatekeeper.

Now, the options I considered and why I don't think any of them are viable.

DISCLAIMER: A lot of the security below will sound like LARPing, fearmongering and paranoid and the reason is because I already have a Netflix account, I don't need access to my media server when I'm travelling. The main reason I have a homelab is LARPing, learning about security and having fun with it.

### Self-hosted VPN

I considered self hosting a VPN, mainly wireguard as it is quite simple and it is difficult to mess up. I could either host the server (as in, the device listening on the internet) at home or on a VPS.

If were to host it at home (here is where the disclaimer becomes important), a carefully crafted packet sent to my VPN by anyone in the world could technically compromise my server so that is discarded.

Hosting the "VPN server" on the cloud is another option however I am basically opening all of my services to the VPS provider. I have tried to "protect" my services with things like TLS client certificates however things that use apps like Nextcloud or Jellyfin don't work with these and solutions that can tunnel the traffic are too complex for my mom. I do not really trust the developers of most of my services to know what they are doing when they listen in port 3675 when Oracle can connect to them.

Also even with very carefully chosen VPS locations I found that the latency for things like video streaming makes it unusable.

### Tailscale/Zerotier

Tailscale and Zerotier work very nicely except for the part that you're completely trusting Tailscale and Zerotier servers. Their servers being compromised would mean that they can now see all of my services. Both of them offer you to self host the server but as far as I know Tailscale self hosted won't work on phones and Zerotier self hosted still talks to Zerotier servers.

### Nebula

Nebula sounds very good as it's basically the same as Tailscale/Zerotier but hosting your on server. The main complaints I found with this are:

- You issue certificates for hosts and there isn't any centralised revocation lists. Revoking a compromised client means going to all of your devices and adding a blacklist rule.
- Phone app doesn't allow setting a custom DNS. If I set the DNS server on my settings means when I disconnect from the network I need to change it again.
- If I host Nebula at home, I'm opening a port to my server, if I host it on the cloud, now the cloud provider can see my flawed services. I can't see a setup where I can restrict my server to only talk to specific clients but not the server. In any scenario the server can say, "I'm Alice now!" and get what they want.

NOTE: I am not familiar of the intricacies of how Nebula works. I am aware that Nebula implements a sort of firewall where you can decide what hosts you want to talk to and which ones to block but I don't trust that a Nebula server can't impersonate a client and bypass any firewall rules. If you are familiar with Nebula's code I'd love some input on this.

### SSH tunnels

Similar problem to setting my own VPN, either I expose my home network to compromise or I give access to a VPS provider to see all of my open services.

Equally, this is TCP over TCP, not great for speed.

### Cloudflare

I refuse to send my traffic in plain HTTP to a Cloudflare server.

### The problems with the web

In addition to that I have a problem with how the web works today: you don't trust the website you're visiting, you trust certificate authorities.

In a usual scenario where Alice wants to access Bob's website:

- Bob creates his website and puts it on a server
- Bob needs to ask a 3rd party to provide him with a domain name
- Bob needs to ask a 3rd party to provide him with a TLS certificate
- Alice then asks a DNS provider: where is bob.com? And she gets an IP address.
- Alice then has a list of certificate authorities that she is supposed to trust and she asks them "Bob's server has given me this response, can I trust that it's Bob?" and then she gets the website.

In this scenario, a compromised DNS server can provide a wrong response. Usually you would say, that's OK because then the malicious server won't have a proper TLS certificate. But if, let's say, Namecheap is compromised, they can point you to their server and issue a TLS certificate for themselves. Same with your ISP. Not safe.

Equally, I want to post a website on the internet so that Alice can see it, why do I need to ask for permission to do this safely? But that gets a bit into the philosophical territory.

### My dream scenario

- When Bob opens his website he decides that Carol will be her introduction point and shares his public key with Carol. He doesn't need to open any port to the internet but he sets up a permanent connection with Carol.
- Alice then wants to access bob.com and she knows that bob.com can be found on Carol's directory (or access Dave's public directory that just has Carol's IP)
- Alice asks Carol if they know how to find bob.com. Carol asks for proof that they know Bob, Alice provides Bob's public key.
- Carol checks that Bob's public key matches and sets up a connection between Alice and Bob via something like UDP hole punching.
- Now that Alice and Bob are connected and Alice has Bob's public key they have a secure point to point channel.

In this situation even if Carol is compromised and redirects Alice to malicious host, that malicious host won't be able to establish a channel with Alice without having Bob's private key.

In the current web, trusting a specific certificate and alerting if it changes wouldn't work, as the same companies that issue your certificate can generate new ones for that domain.

Using your own CA also won't work. If your ISP has the capability of generating TLS certificates they could point you to the wrong address and generate a nice certificate for the wrong bob.com since you are already most likely trusting their certificates by default.

Maybe one option would be to have a browser that only trusts your own certificate to access that specific website, but what do you do if there are 3 more websites that you need to visit? Or a browser that associates CA's with website, e.g. for Bob's website you only trust Bob's CA, etc. I don't see any problems with this except for not having the knowledge to do it myself.

Overall, the idea is that I want to trust endpoints, not any of the middlemen. And that, regardless of what middle men do, ultimately I want to see that the end server is who they think they are. I temporarily trust Carol but only up until the point that I can verify myself that Bob is actually Bob.

At the same time, Bob doesn't need to care about security as much because Carol will, but equally the fact that Carol is responsible for security doesn't mean that Carol has the capability to impersonate Bob. Worth noting that I don't expect Carol to be Carol but rather Carol Inc or Carol.org.

### Tor

If you are familiar with Tor you probably realised by now that in the section above I've described a badly-explained over-simplified version of how Tor works for private onion sites. For the ones that don't know, Tor does basically that: servers trust a middle man but ultimately you use the server's public key to communicate with them and you trust a single public key per site.

The main problem with Tor for this use case is that it's not made for this, it's made for anonymity. While it is true that you can do your normal browsing with Tor there are a few problems:

- Anonymity requires that traffic is relayed through multiple servers, this makes everything very slow. There is a way to single-hop however it is not advised. I wish you could safely setup an end to end connection as a last step.
- Because of the anonymity, it is unusable for normal browsing mainly because of the amount of websites that will block Tor exit nodes, the amount of captchas you will find (looking at you Google) and how slow it is.

Tor sets up the ground for my ideal web, but the focus on anonymity makes it very difficult to use for other purposes.

### What I am currently using

Even after all that I ended up settling for a Wireguard server hosted on the cloud. Being realistic, that is way more than enough security for hosting a few movies and a bunch of documents but again, the whole point was about LARPing about three letter agencies trying to access my data.

### Other thoughts

If there was a way to communicate directly between two wireguard peers without any of them opening ports with the help of a public server then you could even communicate using HTTP. Alice is connecting to Bob with Bob's public Wireguard key and you can even send your traffic over HTTP knowing that the connection is end to end encrypted and they are who they say they are because you know Bob's public key. You wouldn't get the peace of mind of having a lock icon on the browser but that could be implemented.

I haven't even considered things like port-knocking because in the end that's a daemon running with the privilege to alter your firewall rules that I personally trust even less than Wireguard.

### Conclusion

The current web has taught us that we need to trust companies and if companies say it's fine, then you can sleep at night. In my ideal web you trust who you want to talk to and the middle men help establish the connection. No one apart from the destination site has any authority over whether that site can be trusted or not.

Equally most applications want to authenticate themselves. They try really hard to make it securely but being realistic, we all know that applications are bound to eventually have newly discovered huge security holes, whereas software made specifically for security with a small attack surface should be a first door to unlock before actually being able to talk to the service daemon (i.e. I don't want to rely on Apache to protect Nextcloud data hosted on Apache).

If you trust Wireguard to be impenetrable, Wireguard is probably the solution with the best latency being able to even communicate with plain HTTP. However if you want to be as paranoid as me, another layer of protection would be great.

PS: If there is a specific protocol/setup that solves all my problems I would love to hear about it!
