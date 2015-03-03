Thread = require '../../src/flux/models/thread'
Message = require '../../src/flux/models/message'
Contact = require '../../src/flux/models/contact'
NamespaceStore = require '../../src/flux/stores/namespace-store.coffee'
DatabaseStore = require '../../src/flux/stores/database-store.coffee'
DraftStore = require '../../src/flux/stores/draft-store.coffee'
_ = require 'underscore-plus'

fakeThread = new Thread
  id: 'fake-thread-id'
  subject: 'Fake Subject'

fakeMessage1 = new Message
  id: 'fake-message-1'
  to: [new Contact(email: 'ben@nilas.com'), new Contact(email: 'evan@nilas.com')]
  cc: [new Contact(email: 'mg@nilas.com'), NamespaceStore.current().me()]
  bcc: [new Contact(email: 'recruiting@nilas.com')]
  from: [new Contact(email: 'customer@example.com', name: 'Customer')]
  threadId: 'fake-thread-id'
  body: 'Fake Message 1'
  date: new Date(1415814587)

fakeMessage2 = new Message
  id: 'fake-message-2'
  to: [new Contact(email: 'customer@example.com')]
  from: [new Contact(email: 'ben@nilas.com')]
  threadId: 'fake-thread-id'
  body: 'Fake Message 2'
  date: new Date(1415814587)

fakeMessages =
  'fake-message-1': fakeMessage1
  'fake-message-2': fakeMessage2

describe "DraftStore", ->
  describe "creating drafts", ->
    beforeEach ->
      spyOn(DatabaseStore, 'find').andCallFake (klass, id) ->
        return Promise.resolve(fakeThread) if klass is Thread
        return Promise.resolve(fakeMessages[id]) if klass is Message
        return Promise.reject(new Error('Not Stubbed'))
      spyOn(DatabaseStore, 'run').andCallFake (query) ->
        return Promise.resolve(fakeMessage2) if query._klass is Message
        return Promise.reject(new Error('Not Stubbed'))
      spyOn(DatabaseStore, 'persistModel')

    describe "onComposeReply", ->
      beforeEach ->
        runs ->
          DraftStore._onComposeReply({threadId: fakeThread.id, messageId: fakeMessage1.id})
        waitsFor ->
          DatabaseStore.persistModel.callCount > 0
        runs ->
          @model = DatabaseStore.persistModel.mostRecentCall.args[0]

      it "should include quoted text", ->
        expect(@model.body.indexOf('blockquote') > 0).toBe(true)
        expect(@model.body.indexOf(fakeMessage1.body) > 0).toBe(true)

      it "should address the message to the previous message's sender", ->
        expect(@model.to).toEqual(fakeMessage1.from)

      it "should set the replyToMessageId to the previous message's ids", ->
        expect(@model.replyToMessageId).toEqual(fakeMessage1.id)

    describe "onComposeReplyAll", ->
      beforeEach ->
        runs ->
          DraftStore._onComposeReplyAll({threadId: fakeThread.id, messageId: fakeMessage1.id})
        waitsFor ->
          DatabaseStore.persistModel.callCount > 0
        runs ->
          @model = DatabaseStore.persistModel.mostRecentCall.args[0]

      it "should include quoted text", ->
        expect(@model.body.indexOf('blockquote') > 0).toBe(true)
        expect(@model.body.indexOf(fakeMessage1.body) > 0).toBe(true)

      it "should address the message to the previous message's sender", ->
        expect(@model.to).toEqual(fakeMessage1.from)

      it "should cc everyone who was on the previous message in to or cc", ->
        ccEmails = @model.cc.map (cc) -> cc.email
        expectedEmails = [].concat(fakeMessage1.to, fakeMessage1.cc).map (cc) -> cc.email
        expect(ccEmails.sort()).toEqual(expectedEmails.sort())

      it "should not include people who were bcc'd on the previous message", ->
        expect(@model.bcc).toEqual([])
        expect(@model.cc.indexOf(fakeMessage1.bcc[0])).toEqual(-1)

      it "should not include you when you were cc'd on the previous message", ->
        ccEmails = @model.cc.map (cc) -> cc.email
        myEmail = NamespaceStore.current().me().email
        expect(ccEmails.indexOf(myEmail)).toEqual(-1)

      it "should set the replyToMessageId to the previous message's ids", ->
        expect(@model.replyToMessageId).toEqual(fakeMessage1.id)

    describe "onComposeForward", ->
      beforeEach ->
        runs ->
          DraftStore._onComposeForward({threadId: fakeThread.id, messageId: fakeMessage1.id})
        waitsFor ->
          DatabaseStore.persistModel.callCount > 0
        runs ->
          @model = DatabaseStore.persistModel.mostRecentCall.args[0]

      it "should include quoted text", ->
        expect(@model.body.indexOf('blockquote') > 0).toBe(true)
        expect(@model.body.indexOf(fakeMessage1.body) > 0).toBe(true)

      it "should not address the message to anyone", ->
        expect(@model.to).toEqual([])
        expect(@model.cc).toEqual([])
        expect(@model.bcc).toEqual([])

      it "should not set the replyToMessageId", ->
        expect(@model.replyToMessageId).toEqual(undefined)

    describe "_newMessageWithContext", ->
      beforeEach ->
        # A helper method that makes it easy to test _newMessageWithContext, which
        # is asynchronous and whose output is a model persisted to the database.
        @_callNewMessageWithContext = (context, attributesCallback, modelCallback) ->
          runs ->
            DraftStore._newMessageWithContext(context, attributesCallback)
          waitsFor ->
            DatabaseStore.persistModel.callCount > 0
          runs ->
            model = DatabaseStore.persistModel.mostRecentCall.args[0]
            modelCallback(model) if modelCallback

      it "should create a new message", ->
        @_callNewMessageWithContext {threadId: fakeThread.id}
        , (thread, message) ->
          {}
        , (model) ->
          expect(model.constructor).toBe(Message)

      it "should apply attributes provided by the attributesCallback", ->
        @_callNewMessageWithContext {threadId: fakeThread.id}
        , (thread, message) ->
          subject: "Fwd: Fake subject"
          to: [new Contact(email: 'weird@example.com')]
        , (model) ->
          expect(model.subject).toEqual("Fwd: Fake subject")

      describe "when a quoted message is provided by the attributesCallback", ->
        it "should include quoted text in the new message", ->
          @_callNewMessageWithContext {threadId: fakeThread.id}
          , (thread, message) ->
            quotedMessage: fakeMessage1
          , (model) ->
            expect(model.body.indexOf('gmail_quote') > 0).toBe(true)
            expect(model.body.indexOf('Fake Message 1') > 0).toBe(true)

        it "should include the `On ... wrote:` line", ->
          @_callNewMessageWithContext {threadId: fakeThread.id}
          , (thread, message) ->
            quotedMessage: fakeMessage1
          , (model) ->
            expect(model.body.indexOf('On Jan 17 1970, at 1:16 am, Customer <customer@example.com> wrote') > 0).toBe(true)

        it "should only include the sender's name if it was available", ->
          @_callNewMessageWithContext {threadId: fakeThread.id}
          , (thread, message) ->
            quotedMessage: fakeMessage2
          , (model) ->
            expect(model.body.indexOf('On Jan 17 1970, at 1:16 am, ben@nilas.com wrote:') > 0).toBe(true)

      describe "attributesCallback", ->
        describe "when a threadId is provided", ->
          it "should receive the thread", ->
            @_callNewMessageWithContext {threadId: fakeThread.id}
            , (thread, message) ->
              expect(thread).toEqual(fakeThread)
              {}

          it "should receive the last message in the fakeThread", ->
            @_callNewMessageWithContext {threadId: fakeThread.id}
            , (thread, message) ->
              expect(message).toEqual(fakeMessage2)
              {}

        describe "when a threadId and messageId are provided", ->
          it "should receive the thread", ->
            @_callNewMessageWithContext {threadId: fakeThread.id, messageId: fakeMessage1.id}
            , (thread, message) ->
              expect(thread).toEqual(fakeThread)
              {}

          it "should receive the desired message in the thread", ->
            @_callNewMessageWithContext {threadId: fakeThread.id, messageId: fakeMessage1.id}
            , (thread, message) ->
              expect(message).toEqual(fakeMessage1)
              {}