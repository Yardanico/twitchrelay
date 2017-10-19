import os, strutils, parsecfg, asyncdispatch, irc

const
  # Some settings which are not needed in config
  IrcPort = Port(6667)

  TwitchAddr = "irc.chat.twitch.tv"

  # Configuration template
  ConfigTemplate = """
    twitch_nick = "nick"

    # All messages from this channel will be sent to server_chan
    # Twitch channel is basically # + twitch username, like "#araq4k"
    twitch_chan = "#chan"

    # You can get this token here - http://www.twitchapps.com/tmi/
    twitch_token = "token"

    server_addr = "irc.freenode.net"
    server_chan = "#nim"
    server_nick = "FromTwitch"
    
    # Should we log all messages to the terminal?
    log = true
  """.unindent

  CfgPath = "twitchrelay.ini"

if not fileExists(CfgPath):
  writeFile(CfgPath, ConfigTemplate)
  echo "No config file was found, `$1` was created in the current dir!" % CfgPath
  quit(1)

let
  # Load config and choose empty section
  cfg = loadConfig(CfgPath)[""]

  twitchNick = cfg["twitch_nick"]
  twitchChan = cfg["twitch_chan"]
  twitchToken = cfg["twitch_token"]

  # For message logging
  twitchDescr = twitchChan & " on Twitch"
  
  serverAddr = cfg["server_addr"]
  serverChan = cfg["server_chan"]
  serverNick = cfg["server_nick"]
  
  log = cfg["log"].parseBool()

template onEvent(name, ircClient, ircChan): untyped {.dirty.} = 
  proc name(client: AsyncIrc, event: IrcEvent) {.async.} = 
    let isTwitch = twitchChan in event.params[0]

    if event.typ != EvMsg or event.params.len < 2:
      return
    
    # Check if Twitch authentication failed
    elif event.cmd == MNotice and "Improperly" in event.params[1]:
      echo "Twitch authentication failed!"
      quit(1)
    
    # If it's not a PRIVMSG or it's not sent from the channel
    elif event.cmd != MPrivMsg or event.params[0][0] != '#': return
    
    var (nick, msg) = (event.nick, event.params[1])

    # Replace some special chars or strings
    msg = msg.multiReplace({
      "ACTION": "", 
      "\n": "↵", "\r": "↵", "\l": "↵", 
      "\1": ""
    })
    
    # Special case for the Gitter <-> IRC bridge
    if nick == "FromGitter":
      let data = msg.split(">", 1)
      # Probably can't happen
      if data.len != 2: return
      (nick, msg) = (data[0][2..^1], data[1].strip())
      
    let toSend = "<$1> $2" % [nick, msg]

    if log:
      # Check if it's from Twitch
      # We check if Twitch channel name is in the first event parameter
      
      echo "Sending `$1` to $2" % [
        toSend, if isTwitch: serverChan else: twitchDescr
      ]
    # Send message to another IRC server
    # Twitch to IRC, IRC to Twitch
    asyncCheck ircClient.privmsg(ircChan, toSend)

# We need to forward declare these
proc onChanEvent(client: AsyncIrc, event: IrcEvent) {.async.}
proc onTwitchEvent(client: AsyncIrc, event: IrcEvent) {.async.}

# I can't find a way to do it without globals
var twitchClient = newAsyncIrc(
  address = TwitchAddr, port = IrcPort, nick = twitchNick,
  serverPass = twitchToken, joinChans = @[twitchChan], 
  callback = onTwitchEvent
)

var chanClient = newAsyncIrc(
  address = serverAddr, port = IrcPort, nick = serverNick, 
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
  await sleepAsync(3000)
  asyncCheck twitchClient.run()
  asyncCheck chanClient.run()
  echo "Starting TwitchRelay (wait a few seconds)..."

proc hook() {.noconv.} = 
  echo "Disabling TwitchRelay..."
  quit(0)

setControlCHook(hook)
waitFor main()
runForever()