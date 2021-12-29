# storj-system-health.sh

## about this shell script
this linux shell script checks, if a storage node (from the [storj](https://www.storj.io) project) runs into errors and alerts the operator by discord push messages as well as emails. 

**list of features:**
* emails containg an excerpt of the relevant error log message
* if the debug mode is used, disk usage of the mounted data storage disk mount point
* alerts in case a threshold of repair gets/puts and downloads/uploads are reached 
* alerts if there was no get/put at all in the last hour
* alerts in case the node is offline (docker container not started)
* optimized for crontab and command line usage

## example screenshots

an "ok" message

![ok message](/examples/discord-example-all-fine.jpg)

a message saying, that there are fatal errors

![fatal error message](/examples/discord-example-fatal-error.jpg)

another message saying, that there are general errors

![fatal error message](/examples/discord-example-general-error.jpg)

## dependencies
this tool uses the [discord.sh](https://github.com/ChaoticWeg/discord.sh) script to send push messages to your discord channel. 

it also makes use of specific values / selections from the [storj_success_rate.sh](https://github.com/ReneSmeekes/storj_success_rate) script, in order not to reinvent the wheel.

the jq, swaks and curl libraries are required as well. 

## prerequisites
to get notified by a discord push message, you need to setup a webhook on your discord server: [howto](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks). 

you also need to have the [discord.sh](https://github.com/ChaoticWeg/discord.sh) script available and executable in the same folder. 

## configuration
you will need to modify these variables for your specific node and smtp mail server configuration. here's an example to support you entering the right data:
```
                               # your discord webhook url:
URL='https://discord.com/api/webhooks/123456789012345678/ha1Sh3vA5lUe'

MAILFROM="sender@gmail.com"    # your "from:" mail address
MAILTO="addressee@gmail.com"   # your "to:" mail address
MAILSERVER="smtp.server.com"   # your smtp server address
MAILUSER="user123"             # your user name from smtp server
MAILPASS="mypassword123!"      # your password from smtp server
MAILEOF=".. end of mail."      # just a short text marking end of mail

MOUNTPOINT="/mnt/mynode"       # your storage node mount point

NODENAME="storagenode"         # your storagenode docker name
```

make sure, your script is executable by running the following command. add 'sudo' at the beginning, if admin privileges are required. 
```
chmod u+x storj-system-health.sh  # or:
sudo chmod u+x storj-system-health.sh
```

## usage

you can run the script in debug mode to force a push message to your discord channel although no error was found - or without the debug flag to run it in silent mode via crontab (see automation chapter).

```
./storj-system-health.sh debug # for a regular discord push message or:
./storj-system-health.sh # for silent mode
```

it also supports a help command. more commands will be implemented over time.

```
./storj-system-health.sh --help
```

## automation with crontab
to let the health check run automatically, here’s a crontab example, which runs the script each hour: 
```
0  *    * * *   pi      /home/pi/storj-checks.sh debug
```

## contributing

pull requests are welcome. for major changes, please open an issue first to discuss what you would like to change.

## license

[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)
