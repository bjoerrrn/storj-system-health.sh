# storj-system-health.sh

## about this shell script
this linux shell script checks, if a storage node (from the storj project) runs into errors and alerts the operator by discord pushes as well as emails, containg an excerpt of the relevant error log message. if the debug mode is used, it also informs about the disk usage of the mounted disk, which is used for the storj data storage. 

## references
this tool re-uses the [discord.sh](https://github.com/ChaoticWeg/discord.sh) script. 

## prerequisites
in order to get notified by a discord push message, you need to setup a webhook on your discord server: [howto](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)

## configuration
you will need to modify the constants section for your specific node and smtp mail server configuration. here's an example to support you entering the right data:
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
this is a crontab example, which checks on a regular base each 15 mins and sends an informative summary each morning at 8 am. 
```
0  8    * * *   pi      /home/pi/storj-checks.sh debug
*/15 *  * * *   pi      /home/pi/storj-checks.sh
```
