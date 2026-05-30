#!/usr/bin/env python3
import argparse
import getpass
import pathlib
import sys
import time

try:
    import paramiko
except ImportError:
    print("paramiko is required. Install with: python -m pip install --user paramiko", file=sys.stderr)
    raise


COMMANDS = {
    "id.txt": "id; groups",
    "uname.txt": "uname -a",
    "os-release.txt": "cat /etc/os-release 2>/dev/null || true",
    "hostname.txt": "hostnamectl 2>/dev/null || hostname",
    "cmdline.txt": "cat /proc/cmdline",
    "lsblk.txt": "lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,PARTUUID,MOUNTPOINTS",
    "findmnt.txt": "findmnt -R",
    "block-by-name.txt": "ls -l /dev/block/by-name 2>/dev/null || true",
    "disk-by-partlabel.txt": "ls -l /dev/disk/by-partlabel 2>/dev/null || true",
    "drm.txt": "find /sys/class/drm -maxdepth 3 -type f -print 2>/dev/null | sort | xargs -r -I{} sh -c 'echo --- {}; cat {} 2>/dev/null'",
    "input.txt": "cat /proc/bus/input/devices 2>/dev/null; echo; ls -l /dev/input 2>/dev/null",
    "i2c.txt": "find /sys/bus/i2c/devices -maxdepth 2 -type f -name name -print -exec cat {} \\; 2>/dev/null",
    "firmware-mounts.txt": "mount | grep -Ei 'firmware|dsp|persist|modem|bluetooth|efi|boot|linux' || true",
    "dmesg-filtered.txt": "dmesg | grep -Ei 'adreno|gpu|drm|dsi|touch|goodix|novatek|i2c|camera|cam|cci|csiphy|csid|qcom|wifi|bt|battery|charger|audio|adsp|slpi|ipa' || true",
    "network.txt": "ip addr; echo; ip route",
}

ROOT_COMMANDS = {
    "root-partitions.txt": "cat /proc/partitions; echo; blkid 2>/dev/null || true",
    "root-dmesg-full.txt": "dmesg",
}


def run(client, command, password=None, sudo=False, timeout=30):
    if sudo:
        command = "sudo -S -p '' sh -c " + repr(command)
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    if sudo and password:
        stdin.write(password + "\n")
        stdin.flush()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    code = stdout.channel.recv_exit_status()
    return out, err, code


def main():
    parser = argparse.ArgumentParser(description="Collect Xiaomi Pad 6 Linux/postmarketOS facts over SSH.")
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", default="user")
    parser.add_argument("--password", default=None)
    parser.add_argument("--out-dir", default=None)
    parser.add_argument("--no-sudo", action="store_true")
    args = parser.parse_args()

    password = args.password
    if password is None:
        password = getpass.getpass(f"Password for {args.user}@{args.host}: ")

    repo_root = pathlib.Path(__file__).resolve().parents[1]
    if args.out_dir:
        out_dir = pathlib.Path(args.out_dir)
    else:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        out_dir = repo_root / "captures" / f"pipa-linux-{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        args.host,
        22,
        username=args.user,
        password=password,
        look_for_keys=False,
        allow_agent=False,
        timeout=8,
        auth_timeout=8,
        banner_timeout=8,
    )

    print(f"[*] Connected to {args.user}@{args.host}")
    print(f"[*] Writing capture files to {out_dir}")

    for filename, command in COMMANDS.items():
        out, err, code = run(client, command, timeout=45)
        (out_dir / filename).write_text(out + (("\nSTDERR:\n" + err) if err else "") + f"\nEXITCODE={code}\n", encoding="utf-8")

    if not args.no_sudo:
        for filename, command in ROOT_COMMANDS.items():
            out, err, code = run(client, command, password=password, sudo=True, timeout=45)
            (out_dir / filename).write_text(out + (("\nSTDERR:\n" + err) if err else "") + f"\nEXITCODE={code}\n", encoding="utf-8")

    client.close()
    print("[*] Capture complete")


if __name__ == "__main__":
    main()

