{Emitter} = require 'event-kit'
url = require 'url'
_ = require 'underscore-plus'

class InboxLongConnection

  @State =
    Idle: 'idle'
    Ended: 'ended'
    Connecting: 'connecting'
    Connected: 'connected'
    Retrying: 'retrying'

  constructor: (inbox, namespaceId) ->
    @_inbox = inbox
    @_namespaceId = namespaceId
    @_cursorKey = "inbox.#{@_namespaceId}.cursor"
    @_emitter = new Emitter
    @_state = 'idle'
    @_req = null
    @_reqForceReconnectInterval = null
    @_buffer = null

    @_deltas = []
    @_flushDeltasDebounced = _.debounce =>
      @_emitter.emit('deltas-stopped-arriving', @_deltas)
      @_deltas = []
    , 1000

    @
 
  namespaceId: ->
    @_namespaceId
    
  hasCursor: ->
    !!atom.config.get(@_cursorKey)

  withCursor: (callback) ->
    cursor = atom.config.get(@_cursorKey)
    return callback(cursor) if cursor

    stamp = Math.round(new Date().getTime() / 1000.0)
    @_inbox.makeRequest
      path: "/n/#{@_namespaceId}/delta/generate_cursor"
      method: 'POST'
      body: { "start": stamp }
      success: (json) =>
        @setCursor(json['cursor'])
        callback(json['cursor'])

  setCursor: (cursor) ->
    atom.config.set(@_cursorKey, cursor)

  state: ->
    @state

  setState: (state) ->
    @_state = state
    @_emitter.emit('state-change', state)

  onStateChange: (callback) ->
    @_emitter.on('state-change', callback)

  onDeltas: (callback) ->
    @_emitter.on('deltas-stopped-arriving', callback)

  onProcessBuffer: =>
    bufferJSONs = @_buffer.split('\n')
    bufferCursor = null
    return if bufferJSONs.length == 1

    for i in [0..bufferJSONs.length - 2]
      delta = null
      try
        delta = JSON.parse(bufferJSONs[i])
      catch e
        console.log("#{bufferJSONs[i]} could not be parsed as JSON.", e)
      if delta
        throw (new Error 'Received delta with no cursor!') unless delta.cursor
        @_deltas.push(delta)
        @_flushDeltasDebounced()
        bufferCursor = delta.cursor

    # Note: setCursor is slow and saves to disk, so we do it once at the end
    @setCursor(bufferCursor)
    @_buffer = bufferJSONs[bufferJSONs.length - 1]

  start: ->
    return if @_state is InboxLongConnection.State.Ended
    return if @_req

    throw (new Error 'Cannot start polling without auth token.') unless @_inbox.APIToken

    console.log("Long Polling Connection: Starting....")
    @withCursor (cursor) =>
      return if @state is InboxLongConnection.State.Ended
      console.log("Long Polling Connection: Starting for namespace #{@_namespaceId}, token #{@_inbox.APIToken}, with cursor #{cursor}")
      options = url.parse("#{@_inbox.APIRoot}/n/#{@_namespaceId}/delta/streaming?cursor=#{cursor}&exclude_types=event")
      options.auth = "#{@_inbox.APIToken}:"

      if @_inbox.APIRoot.indexOf('https') is -1
        lib = require 'http'
      else
        options.port = 443
        lib = require 'https'

      req = lib.request options, (res) =>
        return @retry() unless res.statusCode == 200
        @_buffer = ''
        res.setEncoding('utf8')
        processBufferThrottled = _.throttle(@onProcessBuffer, 400, {leading: false})
        res.on 'close', => @retry()
        res.on 'data', (chunk) =>
          @_buffer += chunk
          processBufferThrottled()

      req.setTimeout(60*60*1000)
      req.setSocketKeepAlive(true)
      req.on 'error', => @retry()
      req.on 'socket', (socket) =>
        @setState(InboxLongConnection.State.Connecting)
        socket.on 'connect', =>
          @setState(InboxLongConnection.State.Connected)
      req.write("1")

      @_req = req

      # Currently we have trouble identifying when the connection has closed.
      # Instead of trying to fix that, just reconnect every 30 seconds.
      @_reqForceReconnectInterval = setInterval =>
        @retry(true)
      ,30000

  retry: (immediate = false) ->
    return if @_state is InboxLongConnection.State.Ended
    @setState(InboxLongConnection.State.Retrying)
    @cleanup()

    startDelay = if immediate then 0 else 10000
    setTimeout =>
      @start()
    , startDelay

  end: ->
    console.log("Long Polling Connection: Closed.")
    @setState(InboxLongConnection.State.Ended)
    @cleanup()

  cleanup: ->
    clearInterval(@_reqForceReconnectInterval) if @_reqForceReconnectInterval
    @_reqForceReconnectInterval = null
    if @_req
      @_req.end()
      @_req.abort()
      @_req = null

module.exports = InboxLongConnection