# storj-system-health.sh

## about this shell script
this linux shell script checks, if a [storj node][storagenode] ([:storage node] from the [storj][storj] project) runs into errors and alerts the operator by discord push messages as well as emails. requires at least one [storj node][storagenode] running with [docker][docker] on linux.

## features
* multinode support 🌍
* optionally discord (as quick notifications) and/or mail (with error details) alerts 📥 🔔
* alerts when audit, suspension and/or online scores are below a threshold (storj node discqualification risk) ⚠️
* alerts in case a threshold of repair gets/puts and downloads/uploads are reached (storj node discqualification risk) ⚠️
* alerts if there was no get/put at all in the last hour (storj node discqualification risk) ⚠️
* alerts in case the node is offline (docker container not started) ⚠️
* optimized for crontab and command line usage 💻
* only requires [curl][curl], [jq][jq] and [swaks][swaks] to run 🔥

## dependencies
- [storj node][storagenode] node up and running, within a 
- [docker][docker] container
- [curl][curl] (http requests)
- [jq][jq] 1.6 ⚠️ (JSON parsing)
- [swaks][swaks] (mail sending, smtp)
- [discord.sh][discord.sh] (discord pushes)

## setting up storj system health
1. optional: [setup a webhook][webhook] in the desired discord text channel
2. optional: grab your smtp email authentication data
3. download (or clone) a copy of `discord.sh`
4. download (or clone) a copy of `storj-system-health.sh` and `storj-system-health.credo`
5. optional: setup discord and mail variables in `storj-system-health.credo`
6. Go nuts.

## setting up variables in *.credo
you will need to modify these variables in `*.credo` for your specific node and smtp mail server configuration. the `*.credo` file must not include comments and blank lines, the following description is just for your explanation:
```
## discord settings
DISCORDON=true.         # enables (true) or disables (false) discord pushes
DISCORDURL=https://discord.com/api/webhooks/...
                        # your discord webhook url

## mail settings
MAILON=true             # enables (true) or disables (false) email messages
MAILFROM=""             # your "from:" mail address
MAILTO=""               # your "to:" mail address
MAILSERVER=""           # your smtp server address
MAILUSER=""             # your user name from smtp server
MAILPASS=""             # your password from smtp server

## node data mount points
MOUNTPOINTS=/mnt/node   # your storage node mount point, multiple: separated with comma
                        # e.g. /mnt/node,/mnt/node-a,/mnt/node-b

## storj node docker names
NODES=storagenode       # storage node names, multiple: separated with comma, 
                        # e.g. storagenode,storagenode-a,storagenode-b
NODEURLS=localhost:14002
                        # storage node dashboard urls, multiple: separated with comma, 
                        # e.g. localhost:14002,192.168.171.5:14002
```

make sure, your script is executable by running the following command. add 'sudo' at the beginning, if admin privileges are required. 
```
chmod u+x storj-system-health.sh  # or:
sudo chmod u+x storj-system-health.sh

chmod u+x discord.sh  # or:
sudo chmod u+x discord.sh
```

## usage

you can run the script in debug mode to force a push message to your discord channel (if enabled) although no error was found - or without the debug flag to run it in silent mode via crontab (see automation chapter).

```
./storj-system-health.sh -d   # for a regular discord push message or:
./storj-system-health.sh      # for silent mode
```

optionally you can pass another path to `*.credo`, in case it has another name or source:

```
./storj-system-health.sh -c /home/pi/anothername.credo
```

it also supports a help command for further details:

```
./storj-system-health.sh -h
```

## automation with crontab
to let the health check run automatically, here’s a crontab example, which runs the script each hour: 
```
0  *    * * *   pi      /home/pi/storj-checks.sh
```


## example screenshots

an "ok" message

![ok message](/examples/discord-example-all-fine.jpg)

a message saying, that there are fatal errors

![fatal error message](/examples/discord-example-fatal-error.jpg)

another message saying, that there are general errors

![fatal error message](/examples/discord-example-general-error.jpg)


## contributing

pull requests are welcome. for major changes, please open an issue first to discuss what you would like to change.

## license

[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)


<!-- Programs -->
[discord.sh]: https://github.com/ChaoticWeg/discord.sh
[successrates.sh]: https://github.com/ReneSmeekes/storj_success_rate
[curl]: https://curl.haxx.se/
[jq]: https://stedolan.github.io/jq/
[storj]: https://www.storj.io
[docker]: https://github.com/docker
[swaks]: https://github.com/jetmore/swaks
[storagenode]: https://www.storj.io/node
<!-- Documentation -->
[webhook]: https://support.discordapp.com/hc/en-us/articles/228383668-Intro-to-Webhooks
