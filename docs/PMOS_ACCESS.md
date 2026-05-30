# postmarketOS access notes

After switching the connected tablet to slot `b`, Windows no longer saw ADB or
fastboot. It did see a Linux USB serial gadget:

- `USB Serial Device (COM3)`
- USB ID: `VID_0525&PID_A4A2`

No USB RNDIS/network adapter appeared. LAN scan found SSH on:

- `192.168.1.60` with banner `SSH-2.0-OpenSSH_10.0`
- `192.168.1.26` with banner `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.16`

`192.168.1.60` is the likely tablet/postmarketOS host. Key login and common
default passwords failed. To collect Linux details, use the real postmarketOS
username/password:

```powershell
python .\scripts\Collect-PipaLinuxSsh.py --host 192.168.1.60 --user user
```

If USB networking is expected but missing, enable it inside postmarketOS later
with the distribution's network manager or USB gadget configuration. The
current PC only has the serial gadget exposed.

