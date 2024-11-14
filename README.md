# wireguard-xcaler

**wireguard-xcaler** is a project to simplify the management of WireGuard peers at scale.

It creates a FreeBSD jail using [AppJail](https://github.com/DtxdF/AppJail) with WireGuard installed, initializes it with the available parameters and the rest is up to you: run a single command locally or remotely (e.g.: ssh) to create, remove or display a peer's configuration file.

An important difference with [gh+AppJail-makejails/wireguard](https://github.com/AppJail-makejails/wireguard) or “the traditional way” is that it will not restart the WireGuard rc script or create a single big file with all peers. What it does do is change the WireGuard interface parameters at runtime.

## Requirements

1. This project uses the default AppJail Virtual Network when none  is specified, so make sure you have it configured (`AUTO_NETWORK_*` parameters) if you are not happy with the default values.
2. Packet filtering is required to perform NAT and port forwarding, so configure it before deploying this application.
3. The kernel module `if_wg(4)` must be loaded before deploying this application. It is recommended to put `if_wg_load=YES` in your `loader.conf(5)` to load it at startup.

## Installing

```sh
# Clone the repository.
git clone https://github.com/DtxdF/wireguard-xcaler.git

# Switch to the './wireguard-xcaler/' directory.
cd ./wireguard-xcaler/

# Edit the '.env' file to change some parameters.
# Perhaps you may want to change 'appjail-director.yml'.
cp .env.sample .env
$EDITOR .env

# Deploy the VPN server.
appjail-director up
```

## Non-root User

Instead of logging into the jail using `appjail-login(1)` or executing the command to manipulate the peers using `appjail-cmd(1)` `jexec` we can use a combination of scripts and `doas(1)` which has the advantage of executing the commands without user privileges. First, install the mentioned scripts:

```sh
cd ./secure-control/
./install.sh
```

A `doas.conf(5)` file can be found in the [secure-control/run-as/](secure-control/run-as/) directory. Copy it or add it to your `/usr/local/etc/doas.conf` file. Of course, edit it to suit your environment. For example, the user probably does not exist on your system, so change it to your own or even use a group. If you want to use the same user as the one specified in the file:

```sh
pw useradd -n wg-xcaler -s /bin/sh -c "WireGuard-xcaler User" -d /home/wg-xcaler
mkdir -p /home/wg-xcaler
chown wg-xcaler:wg-xcaler /home/wg-xcaler
```

**Available Arguments**:

* `-d` `<destdir>`: Staging directory.
* `-j` `<jail>`: Name of the WireGuard-xcaler jail. 
* `-p` `<prefix>`: Where the script install its files.

## SSH

This project was created with SSH in mind. You just have to add some files on the server and some on the client. First, you must have the scripts installed mentioned in [Non-root User](#non-root-user).

### Server

**sshd_config**:

```
# You can use any keyword you want (for example: 'Group'), but in my
# case I prefer simply 'User'.

Match User wg-xcaler
    ForceCommand /usr/local/bin/wg-xcaler-ssh
    AllowAgentForwarding no
    X11Forwarding no
    # On my server I have `AuthorizedKeys none` configured, so this is
    # necessary. Maybe on your server it is not necessary.
    AuthorizedKeysFile authorized_keys
    Subsystem sftp none
```

**/home/wg-xcaler/authorized_keys**:

```sh
echo "ssh-..." >> /home/wg-xcaler/authorized_keys
```

### Client

**~/.ssh/config**:

```
Match Host wg-xcaler
    HostName <ip-or-hostname>
    User wg-xcaler
    IdentitiesOnly yes
    IdentityFile ~/.ssh/wg-xcaler
    LogLevel ERROR
```

**Note**: I have named the identity file `~/.ssh/wg-xcaler` when creating it using `ssh-keygen(1)`. I strongly recommend using a different SSH key than your personal one.

### Test

```console
$ ssh wg-xcaler
usage: run.sh add <ident>
       run.sh check <ident>
       run.sh del <ident>
       run.sh get-addr <ident>
       run.sh get-network-addr
       run.sh init
       run.sh show <ident>
```

## Managing Peers

To create a new peer just run `wg-xcaler create <identity-string>`. `<identity-string>` is an arbitrary string used to identify a peer. There is no "standard" but I use a convention: `peer://<type>/<identity>/<subtype>`, for example:

```sh
wg-xcaler add peer://users/DtxdF@disroot.org/laptop
```

Similarly, to check whether a peer exists or not:

```console
$ wg-xcaler check peer://users/DtxdF@disroot.org/laptop; echo $?
0
$ wg-xcaler check peer://users/nonexistent@example.org/pc; echo $?
66
```

To obtain the IPv4 address of the specified peer:

```console
$ wg-xcaler get-addr peer://users/DtxdF@disroot.org/laptop
172.16.0.2
```

To display the configuration file of the specified peer:

```console
$ wg-xcaler show peer://users/DtxdF@disroot.org/laptop
[Interface]
PrivateKey = iGcdldXi809VT95iXAvKjG01fuvsQWxfVz7JC30uIGQ=
Address = 172.16.0.2/32
ListenPort = 51820
[Peer]
PresharedKey = ndWZpmmnwqExdDQ5AgCEBp9xPIsqlJOfvpEC62596zs=
PublicKey = RUfRLfdEFL/StqrzNEDuSy7NqWuOWTRVNvlKKRZjbTA=
AllowedIPs = 172.16.0.0/12
Endpoint = x.x.x.x:51820
PersistentKeepalive = 25
$ wg-xcaler show peer://users/DtxdF@disroot.org/laptop | qtencode -t ansiutf8 # QR code.
```

To delete a specified peer:

```sh
wg-xcaler del peer://users/DtxdF@disroot.org/laptop
```

To show the network address:

```console
$ wg-xcaler get-network-addr
172.16.0.0/12
```

And finally, load all the peers. This command is typically executed in the `start` stage.

```sh
wg-xcaler init
```

**Recommendation**: Note that, internally, the peers are actually a directory with a certain structure. The problem is that the names are hashed. I recommend that you keep a simple text file as a list of the peers you have created.

## Makejail Parameters

### Arguments (stage: build)

* `wg_virtualnet` (optional): Virtual Network to use.

### Environment (stage: build)

* `WG_ENDPOINT` (mandatory):  See `Endpoint` in `wg(8)`.
* `WG_PERSISTENTKEEPALIVE` (optional): See `PersistentKeepalive` in `wg(8)`.
* `WG_NETWORK` (default: `172.16.0.0/12`): Network address.
* `WG_PORT` (default: `51820`): See `ListenPort` in `wg(8)`.
* `WG_MTU` (optional): See `MTU` in `wg-quick(8)`.

## Notes

1. If you plan to join the VPN from the same host on which the VPN is deployed, you must change the endpoint to the IPv4 address of the jail instead of using the external IP address. See [www.openbsd.org/faq/pf/rdr.html#reflect](https://www.openbsd.org/faq/pf/rdr.html#reflect)
2. If you change a parameter such as endpoint or network address after recreating the jail, note that the old peers still use the old endpoint and network address, so you will have to change them manually. I do not recommend you to change those parameters after recreating the jail, keep them the same. If you want to use different parameters after recreating the jail, just don't use the same volume.
