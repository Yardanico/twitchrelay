import irc, asyncdispatch, strutils

const
  # Some settings
  IrcPort = Port(6667)

  TwitchAddr = "irc.chat.twitch.tv"
  TwitchNickname = "yardanico"
  TwitchChan = "#" & TwitchNickname
  # You can get this token here - http://www.twitchapps.com/tmi/
  TwitchToken = "oauth:t3coimmq0dn7e0cyjt015jyfw88z6j"
  
  ServerNick = "FromTwitch"
  ServerAddr = "irc.freenode.net"
  ServerChan = "#nim"

template onEvent(name, ircClient, ircChan): untyped {.dirty.} = 
  proc name(client: AsyncIrc, event: IrcEvent) {.async.} = 
    # If event type is not IRC message or event command is not PRIVMSG
    if event.typ != EvMsg or event.cmd != MPrivMsg: return

    # I don't know if this can happen, but who knows :)
    if event.params.len < 2: return
    
    let (nick, msg) = (event.nick, event.params[1])
    await ircClient.privmsg(ircChan, "<$1> $2" % [nick, msg])

proc onChanEvent(client: AsyncIrc, event: IrcEvent) {.async.}
proc onTwitchEvent(client: AsyncIrc, event: IrcEvent) {.async.}

# Yeah, globals are probably bad, but I can't find 
# a way to do it without globals
var twitchClient = newAsyncIrc(
  address = TwitchAddr, port = IrcPort, nick = TwitchNickname,
  serverPass = TwitchToken, joinChans = @[TwitchChan], 
  callback = onTwitchEvent
)

var chanClient = newAsyncIrc(
  address = ServerAddr, port = IrcPort, nick = ServerNick, 
  joinChans = @[ServerChan], callback = onChanEvent
)

# Generate two needed procs
onEvent(onChanEvent, twitchClient, TwitchChan)
onEvent(onTwitchEvent, chanClient, ServerChan)

proc main() {.async.} = 
  # We actually wait for both clients to connect, 
  # and then let them run (almost) simultaneously 
  await twitchClient.connect()
  await chanClient.connect()
  asyncCheck twitchClient.run()
  asyncCheck chanClient.run()

waitFor main()
runForever()