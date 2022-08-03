# storj-system-health.sh

![stars](https://img.shields.io/github/stars/dusselmann/storj-system-health.sh) ![last_commit](https://img.shields.io/github/last-commit/dusselmann/storj-system-health.sh)

this linux/macos shell script checks, if a [storj node][storagenode] (from the [storj][storj] project) runs into errors and alerts the operator by discord push messages as well as emails. requires at least one [storj node][storagenode] running with [docker][docker] on linux.

## features
* multinode support 🌍
* optionally discord (as quick notifications) and/or mail (with error details) alerts 📥 🔔
* alerts, in case: ⚠️
  * audit, suspension and/or online scores are below a threshold (storj node disqualification risk)
  * audit timeouts are recognized (pending audits; discqualification risk) 
  * audit time lags: download started vs. download finished is larger than 3 mins (storj node disqualification risk)
  * a threshold of repair gets/puts and downloads/uploads are reached (storj node disqualification risk)
  * there was no get/put at all in the last hour (storj node disqualification risk)
  * any other fatal error occurs, incl. issues with docker stability
  * storj node version is outdated
  * the node is offline (docker container not started)
* reports: 📰
  * disk usage
  * success rates audits, downloads, uploads, repair up-/downloads
  * estimated payouts for today and current month
  * todays upload and download statistics
* optimized for crontab and command line usage 💻
* supports redirected logs [to a file][log_redirect]
* only requires [curl][curl], [jq][jq], [bc][bc] and (optionally) [swaks][swaks] to run 🔥 

## optimzed / tested for
- debian bullseye 🐧
- macos monterey 🍎 ([jq][jq] + [swaks][swaks] installed with [brew][brew])

## dependencies
- [storj node][storagenode] node up and running, within a 
- [docker][docker] container
- [curl][curl] (http requests)
- [jq][jq] 1.6 ⚠️ (JSON parsing)
- [bc][bc] (arbitrary precision calculator)
- [swaks][swaks] (mail sending, smtp)
- [discord.sh][discord.sh] (discord pushes)

## setting up storj system health
1. optional: [setup a webhook][webhook] in the desired discord text channel
2. optional: grab your smtp email authentication data
3. download (or clone) a copy of `discord.sh` *
4. download (or clone) a copy of `storj-system-health.sh` and `storj-system-health.credo` **
5. optional: setup discord and mail variables in `storj-system-health.credo`
6. Go nuts 🚀

\* `wget https://raw.githubusercontent.com/ChaoticWeg/discord.sh/master/discord.sh` <br/>
\*\* `wget https://raw.githubusercontent.com/dusselmann/storj-system-health.sh/main/storj-system-health.sh && wget https://raw.githubusercontent.com/dusselmann/storj-system-health.sh/main/storj-system-health.credo`

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

## alerting settings
SATPINGFREQ=3600        # in case satellite scores are below threshold, 
                        # value in seconds, when next alert will be sent earliest
                        
## storj node docker names and urls
NODES=storagenode       # storage node names, multiple: separated with comma, 
                        # e.g. storagenode,storagenode-a,storagenode-b
NODEURLS=localhost:14002
                        # storage node dashboard urls, multiple: separated with comma, 
                        # e.g. localhost:14002,192.168.171.5:14002

## node data mount points
MOUNTPOINTS=/mnt/node   # your storage node mount point, multiple: separated with comma
                        # e.g. /mnt/node,/mnt/node-a,/mnt/node-b
                        # enter 'source' from the docker run command here

## specify redirected logs per node
NODELOGPATHS=/          # put your relative path + log file name here,
                        # in case you've redirected your docker logs with
                        # e.g. config.yaml: 'log.output: "/app/config/node.log"'
                        #  /                       -> for non-redirected logs
                        #  /node.log               -> for single node redirect
                        #  /,/                     -> for 2 node with non-redirected logs
                        #  /node1.log,/node2.log   -> for 2 nodes with redirects
                        #  /node.log,/             -> only 1st is redirected
                        #  /mnt/hdd1/node.log      -> full path possible, too

## log selection specifica - in alignment with cronjob settings
LOGMIN=60               # latest log horizon to have a detailled view on, in minutes
                        # -> change this, if your cronjob runs more often than 60m
LOGMAX=720              # larger log horizon for overall statistics, in minutes
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

in order to use the estimated payout information, which looks like so:
```
message:  [sn1] : hdd 38.62% > OK 0.25$ / 11.77$
```
... you should set your crontab to be run around 23:55 UTC. You need to adjust the timing, if you have a couple of nodes and/or huge log files to be analysed: the script needs to be finished before the next full hour, ideally latest 23:59:59 UTC.

it also supports a help command for further details:

```
./storj-system-health.sh -h
```

## automation with crontab
to let the health check run automatically, here’s a crontab example for linux, which runs the script each hour.
```
15,35,55  * * * *   pi      /home/pi/storj-checks.sh -d  > /dev/null
```

for macos please be aware of the following specifics:
* use `crontab -e` and `crontab -l`, although it is depricated (for now it works)
* you do not have to use the user name, it's to be executed with the current user
* use full paths to your script and credo file
* find out your standard path with `echo §PATH` and set it in crontab
```
SHELL=/bin/sh
PATH="/opt/homebrew/opt/sqlite/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# UNIX:
30 *    * * *   pi      cd /home/pi/scripts/ && ./checks.sh
59 1    * * *   pi      cd /home/pi/scripts/ && ./checks.sh -Ed
# MACOS
# 30    * * * *  /Users/me/checks.sh >> /Users/me/Desktop/checks.txt 2>&1
# 59    1 * * *  /Users/me/checks.sh -Ed -c /Users/me/my.credo >> /Users/me/Desktop/checks.txt 2>&1
```

## example screenshots

an "ok" message

![ok message](/examples/discord-example-all-fine.jpg)

a message saying, that there are fatal errors

![fatal error message](/examples/discord-example-fatal-error.jpg)

another message saying, that there are general errors

![general error message](/examples/discord-example-general-error.jpg)

satellite score issues

![satellite issues](/examples/discord-example-satellite-scores.jpg)

success rates per node

![success rates](/examples/discord-example-success-rates.jpg)


## contributing

[issues](https://github.com/dusselmann/storj-system-health.sh/issues) and [pull requests](https://github.com/dusselmann/storj-system-health.sh/pulls) are welcome. for major changes, please open an [issue](https://github.com/dusselmann/storj-system-health.sh/issues) first to discuss what you would like to change.

if you want to contact me directly, feel free to do so via discord: https://discordapp.com/users/371404709262786561

## license

[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)


<!-- Programs -->
[discord.sh]: https://github.com/ChaoticWeg/discord.sh
[successrates.sh]: https://github.com/ReneSmeekes/storj_success_rate
[brew]: https://github.com/Homebrew/brew
[curl]: https://curl.haxx.se/
[bc]: https://www.gnu.org/software/bc/manual/html_mono/bc.html
[jq]: https://stedolan.github.io/jq/
[storj]: https://www.storj.io
[docker]: https://github.com/docker
[swaks]: https://github.com/jetmore/swaks
[storagenode]: https://www.storj.io/node
[log_redirect]: https://docs.storj.io/node/resources/faq/redirect-logs
<!-- Documentation -->
[webhook]: https://support.discordapp.com/hc/en-us/articles/228383668-Intro-to-Webhooks
