# storj-system-health.sh

## about this shell script
this linux shell script checks, if a storage node (from the storj project) runs into errors and alerts the operator by discord pushes as well as emails, containg an excerpt of the relevant error log message. if the debug mode is used, it also informs about the disk usage of the mounted disk, which is used for the storj data storage. 

## references
this tool re-uses the [discord.sh](https://github.com/ChaoticWeg/discord.sh) script. 

## prerequisites
in order to get notified by a discord push message, you need to setup a webhook on your discord server: [howto](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)

## automation
this is a crontab example, which checks on a regular base each 15 mins and sends an informative summary each morning at 8 am. 
```
0  8    * * *   pi      /home/pi/storj-checks.sh debug
*/15 *  * * *   pi      /home/pi/storj-checks.sh
```
