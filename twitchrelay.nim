import os, strutils, parsecfg, asyncdispatch, irc

const
  # Some settings which are not needed in config
  IrcPort = Port(6667)

  TwitchAddr = "irc.chat.twitch.tv"

  ServerAddr = "irc.freenode.net"

  # Configuration template
  ConfigTemplate = """
    twitch_nick = "nick"

    # All messages from this channel will be sent to server_chan
    # Twitch channel is basically # + twitch username, like "#araq4k"
    twitch_chan = "#chan"

    # You can get this token here - http://www.twitchapps.com/tmi/
    twitch_token = "token"

    server_nick = "FromTwitch"
    server_chan = "#nim"

    # Should we log all messages to the terminal?
    log = true
  """.unindent

  ConfigFilename = "twitchrelay.ini"

if not fileExists(ConfigFilename):
  var f = open(ConfigFilename, fmWrite)
  f.write(ConfigTemplate)
  f.close()
  echo "No config file was found, `twitchrelay.ini` was created in the current dir!"
  quit(1)

let
  # Load config and choose empty section (we don't have them in our config)
  cfg = loadConfig(ConfigFilename)[""]

  twitchNick = cfg["twitch_nick"]
  twitchChan = cfg["twitch_chan"]
  twitchToken = cfg["twitch_token"]

  serverNick = cfg["server_nick"]
  serverChan = cfg["server_chan"]

  log = cfg["log"].parseBool()



template onEvent(name, ircClient, ircChan): untyped {.dirty.} = 
  proc name(client: AsyncIrc, event: IrcEvent) {.async.} = 
    # If event type is not IRC message or event command is not PRIVMSG
    if event.typ != EvMsg:
      return
    # Twitch authentication failed
    elif event.cmd == MNotice and "Improperly" in event.params[1]:
      echo "Twitch authentication failed!"
      quit(1)
    # If this event is not a PRIVMSG, return
    elif event.cmd != MPrivMsg: return
    # I don't know if this can happen, but who knows :)
    if event.params.len < 2: return

    let (nick, msg) = (event.nick, event.params[1])
    # Message to send
    let toSend = "<$1> $2" % [nick, msg]
    # If we need to log messages
    if log:
      # Check if it's twitch (we check if twitch channel is in first event param)
      let isTwitch = twitchChan in event.params[0]
      echo "Sending `$1` to $2" % [
        toSend, if isTwitch: "the IRC channel" else: "Twitch"
      ]
    # Send message to another IRC client:
    # Twitch sends to server, server sends to twitch
    await ircClient.privmsg(ircChan, toSend)

# We need to forward declare these
proc onChanEvent(client: AsyncIrc, event: IrcEvent) {.async.}
proc onTwitchEvent(client: AsyncIrc, event: IrcEvent) {.async.}

# Yeah, globals are probably bad, but I can't find 
# a way to do it without globals
var twitchClient = newAsyncIrc(
  address = TwitchAddr, port = IrcPort, nick = twitchNick,
  serverPass = twitchToken, joinChans = @[twitchChan], 
  callback = onTwitchEvent
)

var chanClient = newAsyncIrc(
  address = ServerAddr, port = IrcPort, nick = serverNick, 
  joinChans = @[serverChan], callback = onChanEvent
)

# Generate two needed procs
onEvent(onChanEvent, twitchClient, twitchChan)
onEvent(onTwitchEvent, chanClient, serverChan)

proc main() {.async.} = 
  # We actually wait for both clients to connect, 
  # and then let them run (almost) simultaneously 
  await twitchClient.connect()
  await chanClient.connect()
  asyncCheck twitchClient.run()
  asyncCheck chanClient.run()
  echo "Starting TwitchRelay (wait a few seconds)..."

proc hook() {.noconv.} = 
  echo "Disabling TwitchRelay..."
  # Yes, we don't gracefully close connections to IRC here, 
  # because .close() can sometimes throw an error (especially with async)
  quit(0)

setControlCHook(hook)
waitFor main()
runForever()