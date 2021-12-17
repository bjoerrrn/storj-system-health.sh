# storj-system-health.sh

## about this shell script
this linux shell script checks, if a storage node (from the [storj](https://www.storj.io) project) runs into errors and alerts the operator by discord pushes as well as emails, containg an excerpt of the relevant error log message. if the debug mode is used, it also informs about the disk usage of the mounted disk, which is used for the storj data storage. 

## example screenshots

an "ok" message

![ok message](/examples/discord-example-all-fine.jpg)

a message saying, that there are fatal errors

![fatal error message](/examples/discord-example-fatal-error.jpg)

another message saying, that there are general errors

![fatal error message](/examples/discord-example-general-error.jpg)

## references
this tool uses the [discord.sh](https://github.com/ChaoticWeg/discord.sh) script to send push messages to your discord channel. 

it also makes use of specific values / selections from the [storj_success_rate.sh](https://github.com/ReneSmeekes/storj_success_rate) script, in order not to reinvent the wheel.

## prerequisites
to get notified by a discord push message, you need to setup a webhook on your discord server: [howto](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks). 

you also need to have the [discord.sh](https://github.com/ChaoticWeg/discord.sh) script available in the same folder. 

## configuration
you will need to modify these variables for your specific node and smtp mail server configuration. here's an example to support you entering the right data:
```
                                              # your discord webhook url:
URL='https://discord.com/api/webhooks/123456789012345678/ha1Sh3vA5lUe'

MAILFROM="sender@gmail.com"                   # your "from:" mail address
MAILTO="addressee@gmail.com"                  # your "to:" mail address
MAILSERVER="smtp.server.com"                  # your smtp server address
MAILUSER="user123"                            # your user name from smtp server
MAILPASS="mypassword123!"                     # your password from smtp server
MAILEOF=".. end of mail."                     # just a short text marking end of mail

MOUNTPOINT="/mnt/mynode"                      # your storage node mount point

NODENAME="storagenode"                        # your storagenode docker name
```

## automation
to let the health check run automatically, here’s a crontab example, which runs the script each 15 mins and sends an informative summary each morning at 8 am. 
```
0  8    * * *   pi      /home/pi/storj-checks.sh debug
*/15 *  * * *   pi      /home/pi/storj-checks.sh
```

## contributing

pull requests are welcome. for major changes, please open an issue first to discuss what you would like to change.

## license

[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.en.html)
