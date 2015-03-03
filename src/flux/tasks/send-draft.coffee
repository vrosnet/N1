{isTempId} = require '../models/utils'

Actions = require '../actions'
DatabaseStore = require '../stores/database-store'
Message = require '../models/message'
Task = require './task'
SyncbackDraftTask = require './syncback-draft'

module.exports =
class SendDraftTask extends Task

  constructor: (@draftLocalId) -> super

  shouldDequeueOtherTask: (other) ->
    other instanceof SendDraftTask and other.draftLocalId is @draftLocalId

  shouldWaitForTask: (other) ->
    other instanceof SyncbackDraftTask and other.draftLocalId is @draftLocalId

  performLocal: ->
    # When we send drafts, we don't update anything in the app until
    # it actually succeeds. We don't want users to think messages have
    # already sent when they haven't!
    return Promise.reject("Attempt to call SendDraftTask.performLocal without @draftLocalId") unless @draftLocalId
    Actions.postNotification({message: "Sending message…", type: 'info'})
    Promise.resolve()

  performRemote: ->
    new Promise (resolve, reject) =>
      # Fetch the latest draft data to make sure we make the request with the most
      # recent draft version
      DatabaseStore.findByLocalId(Message, @draftLocalId).then (draft) ->
        # The draft may have been deleted by another task. Nothing we can do.
        return reject(new Error("We couldn't find the saved draft.")) unless draft

        if draft.isSaved()
          body =
            draft_id: draft.id
            version: draft.version
        else
          body = draft.toJSON()

        atom.inbox.makeRequest
          path: "/n/#{draft.namespaceId}/send"
          method: 'POST'
          body: body
          returnsModel: true
          success: ->
            atom.playSound('mail_sent.ogg')
            Actions.postNotification({message: "Sent!", type: 'success'})
            DatabaseStore.unpersistModel(draft).then(resolve)
          error: reject
      .catch(reject)

  onAPIError: ->
    msg = "Our server is having problems. Your message has not been sent."
    @notifyErrorMessage(msg)

  onOtherError: ->
    msg = "We had a serious issue while sending. Your message has not been sent."
    @notifyErrorMessage(msg)

  onTimeoutError: ->
    msg = "The server is taking an abnormally long time to respond. Your message has not been sent."
    @notifyErrorMessage(msg)

  onOfflineError: ->
    msg = "You are offline. Your message has NOT been sent. Please send your message when you come back online."
    @notifyErrorMessage(msg)